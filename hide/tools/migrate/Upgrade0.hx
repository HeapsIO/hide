package hide.tools.migrate;

import hrt.prefab.fx.Value;
import hrt.prefab.fx.Evaluator;
import hide.tools.migrate.Migrate.FileReport;
import hide.tools.migrate.RawNode.get;
import hrt.prefab.Diff.deepCopy;

/** A component of a vector property after the upgrade: `a * old[src] + b`, the value of the prefab when `src` is null **/
private typedef ChannelMap = { src : Null<Int>, a : Float, b : Float };

/** The curves of a vector property: `uniform` when one curve is all of them **/
private typedef Channels = { uniform : RawNode, comps : Array<RawNode> };

/** A sampled re-bake of the rotation (and scale) of an object, `problem` tells why it cannot stand for the old transform **/
private typedef Resample = {
	var cs : Channels;
	var cr : Channels;
	var scale : Array<Float>;
	var rot : Array<Float>;
	var withScale : Bool;
	var loop : Bool;
	/** What the keys are over: "" for the FX time, else an FX parameter **/
	var input : String;
	var scaleKeys : Array<Array<Dynamic>>;
	var rotKeys : Array<Array<Dynamic>>;
	var problem : String;
	/** Why the keys only stand for the old transform at the default of the parameters **/
	var approx : String;
	/** How far the old runtime was from a rigid transform **/
	var nonRigid : Float;
}

/** The mode of a param component (format 1), a curve by its path from the emitter **/
private enum Mode {
	MConstant( v : Float );
	MRange( min : Float, max : Float );
	MCurve( curve : String, from : Float, to : Float );
	MRandomCurve( curve : String, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
	MCurveRange( a : String, aFrom : Float, aTo : Float, b : String, bFrom : Float, bTo : Float );
}

private enum abstract Group(Int) {
	var Spawn;
	var Particle;
	var Multiplier;
}

/** A param with modes of format 1, and the old field it comes from **/
private typedef ParamDef = { name : String, old : String, group : Group, def : Array<Float> };

/**
	Upgrade of the prefab format 0 to 1, on the raw data of one file:

	- Emitter params with modes (`Emitter`, `Emitter2D`, the particle shaders), from the base value,
	  random amount and curves by name of the old params.
	- Animation curves hold the value they animate: the constants the old FX composed them with are
	  baked into them (exactly when the old value is linear in the curve), and the ones of the emitter
	  params are named after what they animate (`startSpeed:x:min`, `scaleMultiplier`).
	- Orbit speeds go from radians to degrees per second.
	- Transforms are re-baked exactly, the curves of the rotation and scale affine in the old ones: the
	  base rotation folded into the euler angles (from another euler triple of the same rotation, which
	  the prefab then stores, when it takes one), the animated scale moved before the base rotation
	  (its components permuted). An object whose rotation the euler curves cannot follow gets a parent
	  object, which takes its name, its place, its position and its animation as it is; it keeps its
	  base rotation and scale and its content, under a new name (`<name>_base`). The paths of the file
	  through it are updated, the ones that read the object get the child. A scale the base rotation
	  shears, and an object that cannot get a parent (`noParent`), are sampled to what the old runtime
	  showed: `setTransform` kept a scale and a quaternion of the animated matrix (a shear is lost). The
	  samples are over the input of the curves: the FX time, or the FX parameter that remaps them.
	- The overrides of the references are rewritten for the upgraded files they override (see
	  `upgradeReference`), reading the other files of the project through the context.

	It writes the data of format 1. The sampled re-bakes evaluate the old curves with the runtime
	(`Curve.makeVal`, `Evaluator`): they rely on it reading the old curves as the old runtime did.
**/
@:access(hide.tools.migrate.Migrate)
class Upgrade0 {

	/** Rotation tolerance of the sampled re-bakes, in degrees **/
	static inline var ROTATION_TOLERANCE = 0.02;
	/** Scale tolerance of the sampled re-bakes, relative **/
	static inline var SCALE_TOLERANCE = 1e-4;
	/** Error of a sampled re-bake beyond which the object gets a parent, relative to the scale of the matrix rows **/
	static inline var MATRIX_TOLERANCE = 5e-4;
	/** Sampling step of the re-bakes, in seconds **/
	static inline var SAMPLE_STEP = 1.0 / 240.0;
	/** Suffix of the name of an object moved under a parent that takes its name **/
	static inline var BASE_SUFFIX = "_base";

	static function num( v : Dynamic, def : Float ) : Float {
		return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : def;
	}

	/** An object with its fields in this order (`[name, value, name, value...]`), as it is written **/
	static function obj( fields : Array<Dynamic> ) : Dynamic {
		var o = {};
		var i = 0;
		while( i < fields.length ) {
			Reflect.setField(o, fields[i], fields[i + 1]);
			i += 2;
		}
		return o;
	}

	static function sameName( a : String, b : String ) return a == b || a.toLowerCase() == b.toLowerCase();

	/** The value a missing field of a curve key (or handle) loads with, see `CurveKey` **/
	static inline var CurveKeyDefault = -1.0;

	var ctx : Migrate.Context;
	var report : FileReport;
	var file : String;
	var root : RawNode;
	var users : Map<RawNode, Array<RawNode>> = new Map();
	var remapUsers : Map<RawNode, Array<RawNode>> = new Map();
	/** The curves that hold their new values **/
	var upgraded = new haxe.ds.ObjectMap<Dynamic, Bool>();
	var parameters : Map<String, Float> = new Map();
	var fxDuration : Float = 5.0;
	var pristine : Dynamic;
	var mirror : hrt.prefab.Prefab;
	var fileRoot : Bool;

	public function new( ctx : Migrate.Context, report : FileReport ) {
		this.ctx = ctx;
		this.file = report.file;
		this.report = report;
	}

	/**
		Upgrades in place `data`, the root of FX data (an FX, an emitter out of any FX), `fileRoot` when it
		is the root of its file (the paths of the curve references start there, they are not written otherwise).
	**/
	public function run( data : Dynamic, fileRoot : Bool ) {
		pristine = deepCopy(data);
		root =RawNode.build(data, null, []);
		this.fileRoot = fileRoot;
		indexUsers(root);
		checkInputs(root);
		fxPass(root);
		emitterPass(root);
	}

	/** Upgrades the overrides of the references of a file, true if any changed **/
	public static function upgradeReferences( data : Dynamic, ctx : Migrate.Context, report : FileReport ) : Bool {
		var u = new Upgrade0(ctx, report);
		u.root = RawNode.build(data, null, []);
		u.fileRoot = true;
		var n = report.changes.length;
		u.referencePass(u.root);
		return report.changes.length > n;
	}

	function warn( node : RawNode, msg : String ) {
		report.warnings.push('$file ${node.path()}: $msg');
	}

	function fail( node : RawNode, msg : String ) {
		report.errors.push('$file ${node.path()}: $msg');
	}

	function change( node : RawNode, kind : String ) {
		report.changes.push({ path: node.path(), kind: kind });
	}

	/** Fresh instances of the prefab classes, by type, for the defaults of their fields **/
	static var defaults = new Map<String, hrt.prefab.Prefab>();

	/**
		The field `name` (the exact name first, else in any case) of the prefab of `n` once loaded: its
		value in the data, else the default of its class. Null when the class has no such field, or is
		not known to this build.
	**/
	static function fieldOf( n : RawNode, name : String ) : Dynamic {
		if( n.cls == null )
			return null;
		var fields = Type.getInstanceFields(n.cls);
		var f = fields.indexOf(name) >= 0 ? name : Lambda.find(fields, f -> f.toLowerCase() == name.toLowerCase());
		if( f == null )
			return null;
		if( Reflect.hasField(n.data, f) )
			return get(n.data, f);
		var inst = defaults.get(n.type);
		if( inst == null )
			defaults.set(n.type, inst = Type.createInstance(n.cls, [null, new hrt.prefab.ContextShared(null, false)]));
		return Reflect.field(inst, f);
	}

	function isLegacy( n : RawNode ) return n.isCurve && !upgraded.exists(n.data);
	function anyLegacy( g : Array<RawNode> ) return Lambda.exists(g, c -> isLegacy(c));
	function markUpgraded( n : RawNode ) upgraded.set(n.data, true);

	// ----------------------------------------------------------------------------------------
	// Paths

	/** The child of `n` at `part` of a path, like `Prefab.locatePrefab`: the exact name first, else `name-N` for the Nth of that name **/
	static function findChild( children : Array<RawNode>, part : String ) : RawNode {
		var found = Lambda.find(children, c -> c.name == part);
		var dash = part.lastIndexOf("-");
		if( found == null && dash > 0 ) {
			var name = part.substr(0, dash), nth = Std.parseInt(part.substr(dash + 1)) ?? 0;
			found = Lambda.find(children, c -> c.name == name && nth-- == 0);
		}
		return found;
	}

	/** Like `Prefab.locatePrefab` from `base`, the root of the file by default **/
	function locate( path : String, ?base : RawNode ) : RawNode {
		if( path == null || (base == null && !fileRoot) )
			return null;
		var p = base ?? root;
		for( part in path.split(".") ) {
			p = findChild(p.children, part);
			if( p == null )
				return null;
		}
		return p;
	}

	/** The path of `node` from the root (`locate`), null if it cannot be written as one. **/
	function pathOf( node : RawNode ) : String {
		if( !fileRoot )
			return null;
		var parts = [];
		var p = node;
		while( p != root ) {
			if( p == null || p.name == "" || p.name.indexOf("-") >= 0 || p.name.indexOf(".") >= 0 )
				return null;
			parts.unshift(p.uniqueName());
			p = p.parent;
		}
		var path = parts.join(".");
		return locate(path) == node ? path : null;
	}

	/** The path of `node` from `base`, like `EmitterParam.resolveCurve` reads it. **/
	static function relPath( base : RawNode, node : RawNode ) : String {
		var parts = [];
		var p = node;
		while( p != base ) {
			parts.unshift(p.uniqueName());
			p = p.parent;
		}
		return parts.join(".");
	}

	// ----------------------------------------------------------------------------------------
	// Curves

	static function blendMode( n : RawNode ) : Int {
		var b : Dynamic = get(n.data, "blendMode");
		if( b == null ) return 0;
		return Std.isOfType(b, Int) ? b : Std.parseInt(Std.string(b)) ?? 0;
	}

	function newCurve( name : String ) : Dynamic {
		var d : Dynamic = obj(["type", "curve", "name", name, "keyMode", 2, "keys", []]);
		upgraded.set(d, true);
		return d;
	}

	/** A name no enabled sibling has (the curves are found by name among the enabled ones) **/
	static function freeName( parent : RawNode, name : String ) {
		var n = name, i = 1;
		while( Lambda.exists(parent.children, c -> c.enabled() && sameName(c.name, n)) )
			n = name + "_" + (i++);
		return n;
	}

	/** The curves the runtime does not read (`Curve.makeVal`): a remap by another curve, a remapped blend or reference, a blend of curves that are not plain **/
	function checkInputs( n : RawNode ) {
		if( n.isCurve ) {
			var remap : String = get(n.data, "remapPath"), b = blendMode(n);
			inline function plain( c : RawNode ) return blendMode(c) == 0 && (get(c.data, "remapPath") ?? "") == "";
			if( remap != null && remap != "" && !StringTools.startsWith(remap, "$param.") )
				fail(n, "time remap by another curve, not supported");
			else if( remap != null && remap != "" && (b == 1 || b == 3) )
				fail(n, "time remap of a blend or a reference, not supported");
			if( (b == 1 || b == 2) && !Lambda.foreach(n.curveChildren().slice(0, 2), c -> plain(c)) )
				fail(n, "blend of curves that are not plain, not supported");
		}
		for( c in n.children )
			checkInputs(c);
	}

	function indexUsers( n : RawNode ) {
		if( n.isCurve ) {
			if( blendMode(n) == 3 ) {
				var t = locate(get(n.data, "blendParam"));
				if( t != null ) {
					var a = users.get(t);
					if( a == null ) users.set(t, a = []);
					a.push(n);
				}
			}
			var remap : String = get(n.data, "remapPath");
			if( remap != null && !StringTools.startsWith(remap, "$param.") ) {
				var t = locate(remap);
				if( t != null ) {
					var a = remapUsers.get(t);
					if( a == null ) remapUsers.set(t, a = []);
					a.push(n);
				}
			}
		}
		for( c in n.children )
			indexUsers(c);
	}

	/** Copies the data of the curve a reference curve uses into it, which stops depending on it. **/
	function dereference( user : RawNode ) {
		var target = locate(get(user.data, "blendParam"));
		if( target == null ) return;
		var s = num(get(user.data, "scale"), 1), o = num(get(user.data, "offset"), 0);
		var copy : Dynamic = deepCopy(target.data);
		// keep what makes the user what it is
		copy.name = user.data.name;
		copy.enabled = get(user.data, "enabled");
		if( get(user.data, "remapPath") != null ) {
			if( get(copy, "remapPath") != null )
				warn(user, "reference to a remapped curve with its own remap, the remap of the reference is kept");
			copy.remapPath = get(user.data, "remapPath");
		}
		if( copy.enabled == null ) Reflect.deleteField(copy, "enabled");
		RawNode.replaceFields(user.data, copy);
		// it holds the old values of the curve it used
		upgraded.remove(user.data);
		users.get(target)?.remove(user);
		user.rebuildChildren();
		// the copy may itself be a reference
		indexUsers(user);
		bakeLinear(user, s, o, false);
	}

	/**
		Changes the values of a curve to `a * value + b`. The curves that reference it are compensated
		to keep reading the same values, unless `compensate` is false.
	**/
	function bakeLinear( n : RawNode, a : Float, b : Float, compensate = true ) {
		if( a == 1 && b == 0 ) return;
		var us = users.get(n);
		if( compensate && us != null )
			for( u in us.copy() ) {
				if( a == 0 ) {
					dereference(u);
					continue;
				}
				var s = num(get(u.data, "scale"), 1), o = num(get(u.data, "offset"), 0);
				RawNode.setField(u.data, "scale", s / a);
				RawNode.setField(u.data, "offset", o - b * s / a);
			}
		if( compensate && remapUsers.exists(n) )
			warn(n, "curve used as the time remap of other curves, they read the upgraded values");
		var d = n.data;
		switch( blendMode(n) ) {
		case 3:
			RawNode.setField(d, "scale", num(get(d, "scale"), 1) * a);
			RawNode.setField(d, "offset", num(get(d, "offset"), 0) * a + b);
		case 1:
			// `Curve.makeVal` blends its first two children
			var cs = [for( i in 0...hxd.Math.imin(2, n.children.length) ) if( n.children[i].isCurve ) n.children[i]];
			if( cs.length == 0 ) warn(n, "blend curve without child curve");
			for( c in cs )
				bakeLinear(c, a, b, compensate);
		default:
			var keys : Array<Dynamic> = get(d, "keys");
			if( keys == null || keys.length == 0 ) {
				// the default keys of `Curve.load`
				var mode = get(d, "keyMode") ?? 2;
				keys = [obj(["time", 0., "value", 0., "mode", mode]), obj(["time", 1., "value", 1., "mode", mode])];
				RawNode.setField(d, "keys", keys);
			}
			for( k in keys ) {
				k.value = a * num(get(k, "value"), CurveKeyDefault) + b;
				for( h in [get(k, "prevHandle"), get(k, "nextHandle")] )
					if( h != null )
						h.dv = a * num(get(h, "dv"), CurveKeyDefault);
			}
		}
	}

	/** A curve that is `a * curve + b`: a reference to it when possible, else a baked copy. **/
	function linearCopy( src : RawNode, parent : RawNode, name : String, a : Float, b : Float ) : RawNode {
		var path = pathOf(src);
		if( path != null ) {
			var d = newCurve(freeName(parent, name));
			d.blendMode = 3;
			d.blendParam = path;
			if( a != 1 ) d.scale = a;
			if( b != 0 ) d.offset = b;
			var n = parent.addChild(d);
			var us = users.get(src);
			if( us == null ) users.set(src, us = []);
			us.push(n);
			return n;
		}
		var d : Dynamic = deepCopy(src.data);
		d.name = freeName(parent, name);
		var n = parent.addChild(d);
		indexUsers(n);
		bakeLinear(n, a, b, false);
		upgraded.set(d, true);
		return n;
	}

	/** Marks the old curves as upgraded. The curves of the emitters are left to them, but the root. **/
	function markAll( n : RawNode, base : RawNode, skipEmitters : Bool ) {
		if( n.parent != null && n.isCurve && Migrate.isEmitter(n.parent.data) && (skipEmitters || n.parent != base) )
			return;
		if( n.isCurve )
			markUpgraded(n);
		for( c in n.children )
			markAll(c, base, skipEmitters);
	}

	// ----------------------------------------------------------------------------------------
	// Old evaluation (sampled re-bakes)

	/** The prefab of `n` in the file as it was read, loaded as plain prefabs with its curves, to evaluate them. **/
	function mirrorOf( n : RawNode ) : hrt.prefab.Prefab {
		if( n.origin == null )
			return null;
		if( mirror == null ) {
			function strip( d : Dynamic ) : Dynamic {
				if( get(d, "type") == "curve" ) return deepCopy(d);
				var o : Dynamic = { name: d.name };
				var ch : Array<Dynamic> = get(d, "children");
				if( ch != null ) o.children = [for( c in ch ) if( c != null ) strip(c)];
				return o;
			}
			mirror = @:privateAccess hrt.prefab.Prefab.createFromDynamic(strip(pristine), null, new hrt.prefab.ContextShared(null, false));
		}
		var p = mirror;
		for( i in n.origin ) {
			if( p == null || i >= p.children.length ) return null;
			p = p.children[i];
		}
		return p;
	}

	/**
		What the value of curve `n` is read at (`Curve.makeVal`), added to `inputs`: "" for the FX time, else
		the name of an FX parameter (a `$param.` remap, a blend on a parameter). Nothing for a constant.
	**/
	function collectInputs( n : RawNode, inputs : Array<String>, depth = 0 ) {
		if( n == null || depth > 16 || isConstant(n) ) return;
		var own = [];
		switch( blendMode(n) ) {
		case 3: collectInputs(locate(get(n.data, "blendParam")), own, depth + 1);
		case 1:
			own.push("");
			var p : String = get(n.data, "blendParam");
			if( p != null ) own.push(p);
		default: own.push("");
		}
		// the shape is read at what the remap is read at
		var remap : String = get(n.data, "remapPath");
		var remapCurve = remap == null || StringTools.startsWith(remap, "$param.") ? null : locate(remap);
		if( remap != null && (remapCurve != null || StringTools.startsWith(remap, "$param.")) ) {
			own.remove("");
			if( remapCurve != null )
				collectInputs(remapCurve, own, depth + 1);
			else
				own.push(remap.substr("$param.".length));
		}
		for( i in own )
			if( inputs.indexOf(i) < 0 )
				inputs.push(i);
	}

	/** Keys of a curve and of what it depends on, for the span of a re-bake over its input. **/
	function collectSpan( n : RawNode, span : { min : Float, max : Float, loop : Bool }, ?keyTimes : Array<Float>, depth = 0 ) {
		if( n == null || depth > 16 ) return;
		var d = n.data;
		if( get(d, "loop") == true ) span.loop = true;
		var remap : String = get(d, "remapPath");
		if( remap != null && !StringTools.startsWith(remap, "$param.") ) {
			// the curve is read at the remapped time, the span is the one of the remap curve
			collectSpan(locate(remap), span, keyTimes, depth + 1);
			return;
		}
		switch( blendMode(n) ) {
		case 3: collectSpan(locate(get(d, "blendParam")), span, keyTimes, depth + 1);
		case 1:
			for( c in n.curveChildren() ) collectSpan(c, span, keyTimes, depth + 1);
		default:
			var keys : Array<Dynamic> = get(d, "keys");
			if( keys == null || keys.length == 0 ) keys = [{ time: 0. }, { time: 1. }];
			for( k in keys ) {
				var t = num(get(k, "time"), CurveKeyDefault);
				if( keyTimes != null ) keyTimes.push(t);
				if( t < span.min ) span.min = t;
				if( t > span.max ) span.max = t;
			}
		}
	}

	/**
		Keys fitting `values` (sampled at `times`) within `tol`: the fewest of a linear fit, a smooth one,
		and a smooth one broken at the kinks of the samples (`fitWith`).
	**/
	static function fitKeys( times : Array<Float>, values : Array<Float>, tol : Float ) : Array<Dynamic> {
		// a time sampled twice once
		var keep = [for( i in 0...times.length ) i == 0 || times[i] > times[i - 1]];
		times = [for( i in 0...keep.length ) if( keep[i] ) times[i]];
		values = [for( i in 0...keep.length ) if( keep[i] ) values[i]];
		var best : Array<Dynamic> = null;
		for( mode in 0...3 ) {
			var keys = fitWith(times, values, tol, mode);
			if( best == null || keys.length < best.length ) best = keys;
		}
		return best;
	}

	/**
		A fit adding a key where it misses the most. `mode` 0: linear keys. 1: a cubic between two keys,
		the slope of the samples at its keys, handles at a third of the segment in time, so the time stays
		linear and the value is the Hermite cubic (`Curve.getVal` reads it at steps of 1/32 of the segment,
		linearly between them), checked between the samples too; a line between two consecutive samples, a
		jump is a Constant key before it. 2: the same, the tangents broken at the kinks.
	**/
	static function fitWith( times : Array<Float>, values : Array<Float>, tol : Float, mode : Int ) : Array<Dynamic> {
		var n = times.length;
		inline function slope( i : Int ) return (values[i + 1] - values[i]) / (times[i + 1] - times[i]);
		// much steeper than the samples around it
		var jump = [for( i in 0...n - 1 ) mode > 0 && n > 2 && Math.abs(values[i + 1] - values[i]) > tol
			&& (i == 0 || Math.abs(slope(i)) > 8 * Math.abs(slope(i - 1))) && (i == n - 2 || Math.abs(slope(i)) > 8 * Math.abs(slope(i + 1)))];
		// a change of slope much sharper than the ones around it
		inline function bend( i : Int ) return i < 1 || i > n - 2 ? 0. : Math.abs(slope(i) - slope(i - 1));
		var kink = [for( i in 0...n ) mode == 2 && i > 0 && i < n - 1 && !jump[i] && !jump[i - 1]
			&& bend(i) * (times[i + 1] - times[i - 1]) > tol * 0.1 && bend(i) > 4 * Math.max(bend(i - 2), bend(i + 2))];
		var mL = [], mR = [];
		for( i in 0...n ) {
			var l = i > 0 && !jump[i - 1], r = i < n - 1 && !jump[i];
			if( l && r && !kink[i] ) {
				var m = (slope(i - 1) * (times[i + 1] - times[i]) + slope(i) * (times[i] - times[i - 1])) / (times[i + 1] - times[i - 1]);
				mL.push(m);
				mR.push(m);
			} else {
				mL.push(l ? slope(i - 1) : r ? slope(i) : 0.);
				mR.push(r ? slope(i) : l ? slope(i - 1) : 0.);
			}
		}
		function at( a : Int, b : Int, t : Float ) {
			var seg = times[b] - times[a];
			if( mode == 0 )
				return values[a] + (values[b] - values[a]) * (t - times[a]) / seg;
			inline function h( u : Float ) {
				var u2 = u * u, u3 = u2 * u;
				return (2 * u3 - 3 * u2 + 1) * values[a] + (u3 - 2 * u2 + u) * seg * mR[a] + (3 * u2 - 2 * u3) * values[b] + (u3 - u2) * seg * mL[b];
			}
			var f = (t - times[a]) / seg * 32, k = Math.floor(f);
			return hxd.Math.lerp(h(k / 32), h((k + 1) / 32), f - k);
		}
		var keep = [for( i in 0...n ) i == 0 || i == n - 1 || jump[i] || (i > 0 && jump[i - 1]) || kink[i]];
		var stack = [], prev = 0;
		for( i in 1...n )
			if( keep[i] ) {
				stack.push(prev); stack.push(i);
				prev = i;
			}
		while( stack.length > 0 ) {
			var b = stack.pop(), a = stack.pop();
			if( b == a + 1 ) continue;
			var worst = -1, err = tol;
			for( i in a...b ) {
				var e = i == a ? 0 : Math.abs(at(a, b, times[i]) - values[i]);
				if( mode > 0 )
					e = Math.max(e, Math.abs(at(a, b, (times[i] + times[i + 1]) * 0.5) - (values[i] + values[i + 1]) * 0.5));
				if( e > err ) {
					err = e;
					worst = i == a ? a + 1 : i;
				}
			}
			if( worst >= 0 ) {
				keep[worst] = true;
				stack.push(a); stack.push(worst);
				stack.push(worst); stack.push(b);
			}
		}
		var idx = [for( i in 0...n ) if( keep[i] ) i];
		// a constant curve is one key
		if( idx.length == 2 && Math.abs(values[0] - values[n - 1]) <= tol )
			return [obj(["time", times[0], "value", values[0], "mode", 2])];
		var keys = [];
		for( j => i in idx ) {
			var k : Dynamic = obj(["time", times[i], "value", values[i], "mode", mode == 0 ? 2 : i < n - 1 && jump[i] ? 3 : mL[i] != mR[i] ? 1 : 0]);
			if( mode > 0 && j > 0 && idx[j - 1] < i - 1 ) {
				var dt = (times[i] - times[idx[j - 1]]) / 3;
				k.prevHandle = obj(["dt", -dt, "dv", -mL[i] * dt]);
			}
			if( mode > 0 && j < idx.length - 1 && idx[j + 1] > i + 1 ) {
				var dt = (times[idx[j + 1]] - times[i]) / 3;
				k.nextHandle = obj(["dt", dt, "dv", mR[i] * dt]);
			}
			keys.push(k);
		}
		return keys;
	}

	/** A plain curve whose keys all have the same value **/
	static function isConstant( n : RawNode ) {
		if( blendMode(n) != 0 || get(n.data, "remapPath") != null ) return false;
		var keys : Array<Dynamic> = get(n.data, "keys");
		if( keys == null || keys.length == 0 ) return false;
		for( k in keys ) {
			if( num(get(k, "value"), CurveKeyDefault) != num(get(keys[0], "value"), CurveKeyDefault) ) return false;
			for( h in [get(k, "prevHandle"), get(k, "nextHandle")] )
				if( h != null && num(get(h, "dv"), CurveKeyDefault) != 0 ) return false;
		}
		return true;
	}

	// ----------------------------------------------------------------------------------------
	// FX

	/** The outermost FX of the file get their animations upgraded. **/
	function fxPass( n : RawNode ) {
		var is2D = n.isA(hrt.prefab.fx.FX2D);
		if( n.isA(hrt.prefab.fx.FX) || is2D ) {
			var params : Array<Dynamic> = get(n.data, "parameters");
			parameters = new Map();
			if( params != null )
				for( p in params )
					parameters.set(get(p, "name"), num(get(p, "def"), 0));
			// the default duration of an FX
			fxDuration = num(get(n.data, "duration"), 5.0);
			prepareEmitters(n);
			process(n, is2D, false);
			markAll(n, n, true);
			return;
		}
		for( c in n.children.copy() )
			fxPass(c);
	}

	/**
		The emitters upgrade their own curves next: the curves that reference the ones they bake are
		made independent first (they would read the new values otherwise).
	**/
	function prepareEmitters( n : RawNode ) {
		if( Migrate.isEmitter(n.data) ) {
			for( c in n.children )
				if( isLegacy(c) && isEmitterAnim(c.name) ) {
					var us = users.get(c);
					if( us != null )
						for( u in us.copy() ) {
							warn(u, "reference to a curve of an emitter, made a copy of it");
							dereference(u);
						}
				}
		}
		for( c in n.children )
			prepareEmitters(c);
	}

	/** The old names of the curves the emitters bake: settings, spawn params and multipliers. **/
	static var EMITTER_ANIMS = ["emitrate", "emitratemin", "emitratemax", "burstparticlecount", "emitangle", "emitradius", "emitangle1", "emitangle2",
		"emitwidth", "emitheight", "inststartspeed", "inststartworldspeed", "instscaleovertime", "instorbitspeedovertime"];

	static function isEmitterAnim( name : String ) {
		return EMITTER_ANIMS.indexOf(name.split(":")[0].toLowerCase()) >= 0;
	}

	function process( n : RawNode, is2D : Bool, inEmitter : Bool ) {
		// what its curves animate, and from which values, depends on its class
		if( n.cls == null && Lambda.exists(n.children, c -> c.isCurve && c.enabled()) )
			fail(n, 'prefab type ${n.type} unknown to this build: its curves are not upgraded (the migration must be built with the prefab classes of the game, see hide/migrate.hxml)');
		if( !is2D && !inEmitter && n.isA(hrt.prefab.Object3D) )
			upgradeObject3D(n);
		if( is2D && n.isA(hrt.prefab.Object2D) )
			upgradeObject2D(n);
		if( (n.isA(hrt.prefab.Shader) && particleEmitter(n) == null) || n.isA(hrt.prefab.rfx.ScreenShaderGraph) )
			upgradeShader(n);
		var em = n.isA(hrt.prefab.fx.Emitter);
		// a parent may be inserted above a child, which is then processed through it
		for( c in n.children.copy() ) {
			var cur = c.parent == n ? c : c.parent;
			process(cur, is2D, inEmitter || em);
		}
	}

	/** Mirrors `Shader.getParticleEmitter`: the shaders under an emitter are evaluated over the particle life. **/
	static function particleEmitter( n : RawNode ) : RawNode {
		var p = n.parent;
		while( p != null ) {
			if( p.isA(hrt.prefab.fx.Emitter) ) return p;
			if( p.isA(hrt.prefab.l3d.Trails) ) return null;
			p = p.parent;
		}
		return null;
	}

	/** The enabled curves named `name` or `name:...`, like `Curve.getCurves` **/
	static function group( n : RawNode, name : String ) : Array<RawNode> {
		return [for( c in n.children ) if( c.isCurve && c.enabled() && sameName(c.name.split(":")[0], name) ) c];
	}

	static function isTransformCurve( c : RawNode ) {
		if( !c.isCurve ) return false;
		var prefix = c.name.split(":")[0];
		return sameName(prefix, "position") || sameName(prefix, "scale") || sameName(prefix, "rotation");
	}

	/** Like `BaseFXTools.vectorAnimation`: the curve of each component, `uniform` when one curve is all of them. **/
	static function channels( curves : Array<RawNode>, name : String, dim : Int ) : Channels {
		if( curves.length == 1 && curves[0].name == name )
			return { uniform: curves[0], comps: [for( _ in 0...dim ) curves[0]] };
		return { uniform: null, comps: [for( i in 0...dim ) {
			var suffix = ":" + ["x", "y", "z", "w"][i];
			Lambda.find(curves, c -> StringTools.endsWith(c.name.toLowerCase(), suffix));
		}] };
	}

	static var COMPONENTS = ["x", "y", "z", "w"];

	/** Applies `a[i] * value + b[i]` to the curves of a vector property **/
	function bakeVector( owner : RawNode, prop : String, ch : Channels, a : Array<Float>, b : Array<Float>, kind : String ) {
		applyMap(owner, prop, ch, [for( i in 0...a.length ) { src: ch.comps[i] == null ? null : i, a: a[i], b: b[i] }], kind);
	}

	function upgradeObject3D( n : RawNode ) {
		var d = n.data;
		var pos = [for( f in ["x", "y", "z"] ) num(fieldOf(n, f), 0)];
		var scale = [for( f in ["scaleX", "scaleY", "scaleZ"] ) num(fieldOf(n, f), 1)];
		var rot = [for( f in ["rotationX", "rotationY", "rotationZ"] ) num(fieldOf(n, f), 0)];

		// position: offset of the base position
		var gp = group(n, "position");
		if( anyLegacy(gp) )
			bakeVector(n, "position", channels(gp, "position", 3), [1, 1, 1], pos, "position");

		// local rotation: offsets of the leaves, now in degrees
		var glr = group(n, "localRotation");
		if( anyLegacy(glr) )
			bakeVector(n, "localRotation", channels(glr, "localRotation", 3), [360, 360, 360], [0, 0, 0], "local rotation");

		var gs = group(n, "scale"), gr = group(n, "rotation");
		if( !anyLegacy(gs) && !anyLegacy(gr) )
			return;
		var cs = gs.length == 0 ? null : channels(gs, "scale", 3);
		var cr = gr.length == 0 ? null : channels(gr, "rotation", 3);

		// old transform: base scale * base rotation * scale(t) * rotation(t) (row vectors, the base first)
		// the animated scale moves before the base rotation: base rotation * scale(t) = scale'(t) * base rotation
		var scaleMap : Array<ChannelMap> = null;
		if( cs != null ) {
			var perm = TransformMath.scalePermutation(rot, classes(cs));
			if( perm != null )
				scaleMap = [for( i in 0...3 ) { src: cs.comps[perm[i]] == null ? null : perm[i], a: scale[i], b: 0. }];
		}
		// base rotation * rotation(t) as euler angles affine in the curves, from an euler triple of the base rotation
		var form = cr == null ? null : TransformMath.rotationForm(rot, classes(cr));
		var shear = cs != null && scaleMap == null;
		var problem = shear ? "scale through the base rotation (shear)" : cr != null && form == null ? "rotation the euler angles cannot follow" : null;
		if( problem != null ) {
			var kept = noParent(n);
			if( kept == null && !shear ) {
				insertParent(n, problem);
				return;
			}
			// the parent would show the shear the old runtime dropped, or there is none: sampled
			var fit = resample(n, shear ? cs : null, cr, scale, rot, shear);
			if( fit.problem != null && kept == null ) {
				insertParent(n, fit.problem);
				return;
			}
			writeResample(n, fit, kept == null ? problem : '$problem, $kept');
			if( !shear && cs != null )
				applyMap(n, "scale", cs, scaleMap, "scale, with rotation");
			return;
		}
		if( cr != null ) {
			var b = form.base;
			if( b[0] != rot[0] || b[1] != rot[1] || b[2] != rot[2] ) {
				// the same base rotation, as the euler triple the curves go from
				for( i => f in ["rotationX", "rotationY", "rotationZ"] ) RawNode.setField(d, f, b[i]);
				change(n, "base rotation as another euler triple");
			}
			var rotMap = [for( j in 0...3 ) {
				var k = form.perm[j];
				cr.comps[k] == null ? { src: null, a: 0., b: b[j] } : { src: k, a: 360. * form.sign[j], b: b[j] };
			}];
			applyMap(n, "rotation", cr, rotMap, rot[0] == 0 && rot[1] == 0 && rot[2] == 0 ? "rotation" : "rotation, base rotation folded");
		}
		if( cs != null )
			applyMap(n, "scale", cs, scaleMap, cr == null ? "scale" : "scale, with rotation");
	}

	/** The class of each component of a vector property for `TransformMath`: the same for the same curve or curves of the same data, -1 for none **/
	static function classes( ch : Channels ) : Array<Int> {
		function key( c : RawNode ) {
			var d = Reflect.copy(c.data);
			Reflect.deleteField(d, "name");
			return haxe.Json.stringify(d);
		}
		var keys = [for( c in ch.comps ) c == null ? null : key(c)];
		return [for( i in 0...3 ) keys[i] == null ? -1 : keys.indexOf(keys[i])];
	}

	/**
		Why the object `n` cannot get a parent (`insertParent`), null when it can: the parent takes its
		animation and the object keeps its world transform, but what reads the transform of its parent
		object, sets its own rotation or reads its direct children would then see another one.
	**/
	function noParent( n : RawNode ) : String {
		if( n.parent == null || n.isA(hrt.prefab.fx.FX) )
			return "the root of the FX cannot get a parent";
		// particles in the space of the parent object, its scale and the local position of the emitter
		if( n.isA(hrt.prefab.fx.Emitter) )
			return "an emitter reads its parent object";
		if( n.isA(hrt.prefab.fx.Swarm) )
			return "a swarm reads its parent object";
		// the parent would turn the rotation they set
		if( n.type == "billboard" )
			return "a billboard sets its own rotation";
		var lock : Array<Float> = get(n.data, "lockAxis");
		if( n.isA(hrt.prefab.fx.LookAt) && lock != null && Lambda.exists(lock, v -> v != 0) )
			return "a look at with a lock axis sets its own rotation";
		// templates and shader holders: their direct children
		for( cl in ([hrt.prefab.fx.ShaderTarget, hrt.prefab.fx.Swarm, hrt.prefab.fx.gpuemitter.GPUEmitter] : Array<Class<hrt.prefab.Prefab>>) )
			if( n.parent.isA(cl) )
				return 'the ${n.parent.type} reads its direct children';
		// the animations of the leaves (`localRotation`) would take the object, which only has transform curves
		if( !Lambda.exists(n.children, c -> !isTransformCurve(c)) ) {
			var p = n.parent;
			while( p != null ) {
				if( group(p, "localRotation").length > 0 || group(p, "localPosition").length > 0 )
					return "it would become a leaf of the local animation of " + p.name;
				p = p.parent;
			}
		}
		return null;
	}

	/**
		Sets the curves of a vector property from the old ones: component `i` becomes `a * old[src] + b`,
		or the value of the prefab (`b`, no curve) when `src` is null.
	**/
	function applyMap( owner : RawNode, prop : String, ch : Channels, map : Array<ChannelMap>, kind : String ) {
		var u = ch.uniform;
		if( u != null ) {
			if( !isLegacy(u) ) return;
			var same = true;
			for( m in map ) if( m.src == null || m.a != map[0].a || m.b != map[0].b ) same = false;
			if( same ) {
				bakeLinear(u, map[0].a, map[0].b);
				markUpgraded(u);
				change(u, kind + ", uniform");
				return;
			}
			// the uniform curve stays as the shape of its components
			var any = false;
			for( i in 0...map.length )
				if( map[i].src != null ) {
					linearCopy(u, owner, prop + ":" + COMPONENTS[i], map[i].a, map[i].b);
					any = true;
				}
			if( !any && (!users.exists(u) || users.get(u).length == 0) ) RawNode.setField(u.data, "enabled", false);
			markUpgraded(u);
			change(u, kind + ", uniform split");
			return;
		}
		var orig = [for( c in ch.comps ) c == null ? null : deepCopy(c.data)];
		for( i in 0...map.length ) {
			var m = map[i];
			var node = ch.comps[i];
			if( m.src == i ) {
				if( isLegacy(node) ) {
					bakeLinear(node, m.a, m.b);
					markUpgraded(node);
					change(node, kind);
				}
				continue;
			}
			if( m.src == null ) {
				// the value of the prefab: the curve is not read anymore
				if( node != null && isLegacy(node) ) {
					RawNode.setField(node.data, "enabled", false);
					markUpgraded(node);
					change(node, kind + ", moved to another component");
				}
				continue;
			}
			// another component: a copy of its old curve
			var d : Dynamic = deepCopy(orig[m.src]);
			d.name = node != null ? node.data.name : freeName(owner, prop + ":" + COMPONENTS[i]);
			if( node != null ) {
				var en : Dynamic = get(node.data, "enabled");
				if( en == null ) Reflect.deleteField(d, "enabled") else d.enabled = en;
			}
			var target = node;
			if( target == null )
				target = owner.addChild(d);
			else
				replaceData(target, d);
			indexUsers(target);
			bakeLinear(target, m.a, m.b, false);
			markUpgraded(target);
			change(target, kind + ", from another component");
		}
	}

	/** Replaces the data of a curve, the curves that referenced it get its old data. **/
	function replaceData( node : RawNode, d : Dynamic ) {
		var us = users.get(node);
		if( us != null )
			for( u in us.copy() ) dereference(u);
		RawNode.replaceFields(node.data, d);
		node.rebuildChildren();
	}

	/**
		Samples the old transform of an object and fits the rotation (and the scale when `withScale`)
		with linear keys, over what its curves are read at: the FX time, or the FX parameter they are all
		remapped by (the keys are then remapped by it too). `problem` tells why the keys cannot stand for
		the old transform, null when they do (checked against the old transform over the whole span).
		Curves read at several inputs are sampled over one of them, the others at their default (`approx`).
	**/
	function resample( n : RawNode, cs : Channels, cr : Channels, scale : Array<Float>, rot : Array<Float>, withScale : Bool ) : Resample {
		var involved : Array<RawNode> = [];
		for( ch in [cs, cr] )
			if( ch != null )
				for( c in ch.comps )
					if( c != null && involved.indexOf(c) < 0 )
						involved.push(c);
		// the input the keys are sampled over: the FX time, or the FX parameter all the curves are read at
		var inputs = [];
		for( c in involved )
			collectInputs(c, inputs);
		var input = inputs.length == 0 || inputs.indexOf("") >= 0 ? "" : inputs[0];
		inline function inputName( i : String ) return i == "" ? "the FX time" : "parameter " + i;
		var approx = inputs.length < 2 ? null : 'depends on ${[for( i in inputs ) inputName(i)].join(", ")}: sampled over ${inputName(input)}, the others at the default of the parameters';
		var span = { min: 0., max: 0., loop: false };
		var keyTimes = [];
		var periods = [];
		var varyingOnce = false;
		for( c in involved ) {
			var cspan = { min: 0., max: 0., loop: false };
			collectSpan(c, cspan, keyTimes);
			if( cspan.min < span.min ) span.min = cspan.min;
			if( cspan.max > span.max ) span.max = cspan.max;
			if( cspan.loop ) {
				span.loop = true;
				if( periods.indexOf(cspan.max) < 0 ) periods.push(cspan.max);
			} else if( !isConstant(c) )
				varyingOnce = true;
		}
		// all the curves loop: the re-bake loops over their common period, else it covers the FX
		var period = TransformMath.commonPeriod(periods);
		var loop = input == "" && span.loop && !varyingOnce && period > 0 && span.min >= 0;
		if( input != "" ) {
			// the range of a blend parameter and its default, and beyond, where the curves are read clamped: the
			// keys then span more than `Curve.BAKE_MAX_DURATION`, the runtime does not smooth their steps
			var def = parameters.get(input) ?? 0.;
			span.min = Math.min(span.min, Math.min(0, def)) - 0.5;
			span.max = Math.max(span.max, Math.max(1, def)) + 0.5;
		} else if( loop ) {
			span.min = 0;
			span.max = period;
		} else {
			var duration = fxDuration > 0 ? fxDuration : 5.0;
			if( span.loop && span.max < duration ) span.max = duration;
			span.max += 1;
		}

		var ev = new Evaluator();
		for( k => v in parameters ) ev.parameters.set(k, v);
		function val( c : RawNode ) : Value {
			if( c == null ) return null;
			var p = Std.downcast(mirrorOf(c), hrt.prefab.Curve);
			return p?.makeVal();
		}
		var sv = cs == null ? [null, null, null] : [for( c in cs.comps ) val(c)];
		var rv = cr == null ? [null, null, null] : [for( c in cr.comps ) val(c)];

		var times = [];
		var steps = Math.ceil((span.max - span.min) / SAMPLE_STEP);
		if( steps > 20000 ) steps = 20000;
		if( steps < 1 ) steps = 1;
		for( i in 0...steps + 1 )
			times.push(span.min + (span.max - span.min) * i / steps);
		// the keys, and around them for the steps
		for( t in keyTimes )
			for( x in [t - 1e-5, t, t + 1e-5] )
				if( x > span.min && x < span.max )
					times.push(x);
		times.sort(Reflect.compare);

		var base = new h3d.Matrix();
		base.initScale(withScale ? scale[0] : 1, withScale ? scale[1] : 1, withScale ? scale[2] : 1);
		base.rotate(hxd.Math.degToRad(rot[0]), hxd.Math.degToRad(rot[1]), hxd.Math.degToRad(rot[2]));
		var m = new h3d.Matrix(), q = new h3d.Quat(), tmp = new h3d.Matrix(), sc = new h3d.Vector();
		// at `x` of the input
		function rawMatrix( x : Float, out : h3d.Matrix ) {
			var t = x;
			if( input != "" ) {
				ev.parameters.set(input, x);
				t = 0;
			}
			inline function f( v : Value, def : Float ) return v == null ? def : ev.getFloat(v, t);
			var s = withScale ? [f(sv[0], 1), f(sv[1], 1), f(sv[2], 1)] : [1., 1., 1.];
			out.initScale(s[0], s[1], s[2]);
			out.rotate(f(rv[0], 0) * Math.PI * 2, f(rv[1], 0) * Math.PI * 2, f(rv[2], 0) * Math.PI * 2);
			out.multiply(base, out);
			return s;
		}
		// the old runtime set it with h3d.scene.Object.setTransform, which keeps a scale and a quaternion: a
		// shear is lost, and the rotation of the previous frame stays while a scale is 0
		function rotationAt( t : Float, depth : Int ) {
			rawMatrix(t, tmp);
			var sc = tmp.getScale();
			if( Math.abs(sc.x) > hxd.Math.EPSILON && Math.abs(sc.y) > hxd.Math.EPSILON && Math.abs(sc.z) > hxd.Math.EPSILON ) {
				tmp.prependScale(1 / sc.x, 1 / sc.y, 1 / sc.z);
				q.initRotateMatrix(tmp);
			} else if( depth < 60 )
				rotationAt(t - 1 / 60, depth + 1);
			else
				q.initRotation(hxd.Math.degToRad(rot[0]), hxd.Math.degToRad(rot[1]), hxd.Math.degToRad(rot[2]));
		}
		// its scale and rotation, `out`: the quaternion of a sheared matrix is not normalized, the runtime then
		// showed a transform that is not a scale and a rotation, the closest one is with the quaternion normalized
		var loss = 0.;
		function oldTransform( t : Float, out : h3d.Matrix ) {
			rawMatrix(t, out);
			sc.load(out.getScale());
			rotationAt(t, 0);
			loss = Math.max(loss, Math.abs(q.lengthSq() - 1));
			q.normalize();
			q.toMatrix(out);
		}
		// the closest scale and euler angles, the euler angles closest to `prevR` and the scales to `prevS`: the
		// scales getScale gives all change sign when one goes through 0, the same transform as two of them
		// changing sign with a half turn about the third axis
		function sampleAt( t : Float, prevR : Array<Float>, prevS : Array<Float> ) : { s : Array<Float>, r : Array<Float>, error : Float, m : h3d.Matrix } {
			oldTransform(t, m);
			var s = [sc.x, sc.y, sc.z];
			function dist( v : Array<Float> ) {
				var d = 0.;
				for( i in 0...3 ) d += (v[i] - prevS[i]) * (v[i] - prevS[i]);
				return d;
			}
			var turn = -1;
			for( k in 0...3 )
				if( dist([for( i in 0...3 ) i == k ? s[i] : -s[i]]) < dist(turn < 0 ? s : [for( i in 0...3 ) i == turn ? s[i] : -s[i]]) )
					turn = k;
			if( turn >= 0 ) {
				var f = [for( i in 0...3 ) i == turn ? 1. : -1.];
				m.prependScale(f[0], f[1], f[2]);
				s = [for( i in 0...3 ) s[i] * f[i]];
			}
			var d = TransformMath.decompose(m, prevR, [1., 1., 1.]);
			d.s = [d.s[0] * s[0], d.s[1] * s[1], d.s[2] * s[2]];
			d.m.prependScale(s[0], s[1], s[2]);
			return d;
		}
		// samples, refined where the linear keys between two of them would miss the transform
		var samples = [];
		var prev = { r: [for( r in rot ) hxd.Math.degToRad(r)], s: withScale ? scale : [1., 1., 1.] };
		for( t in times ) {
			var d = sampleAt(t, prev.r, prev.s);
			prev = d;
			samples.push({ t: t, d: d });
		}
		var rtol = hxd.Math.degToRad(ROTATION_TOLERANCE);
		function refine( a : { t : Float, d : Dynamic }, b : { t : Float, d : Dynamic }, depth : Int, out : Array<{ t : Float, d : Dynamic }> ) {
			if( depth > 0 && b.t - a.t > 1e-6 ) {
				var tm = (a.t + b.t) * 0.5;
				var dm = sampleAt(tm, a.d.r, a.d.s);
				var bad = false;
				for( i in 0...3 ) {
					if( Math.abs(dm.r[i] - (a.d.r[i] + b.d.r[i]) * 0.5) > rtol ) bad = true;
					var sv = (a.d.s[i] + b.d.s[i]) * 0.5;
					if( withScale && Math.abs(dm.s[i] - sv) > SCALE_TOLERANCE * Math.max(1, Math.abs(scale[i])) ) bad = true;
				}
				if( bad ) {
					var mid = { t: tm, d: (dm : Dynamic) };
					refine(a, mid, depth - 1, out);
					out.push(mid);
					refine(mid, b, depth - 1, out);
				}
			}
		}
		var all = [samples[0]];
		for( i in 1...samples.length ) {
			refine(samples[i - 1], samples[i], 10, all);
			all.push(samples[i]);
		}
		times = [for( x in all ) x.t];
		var outS = [for( i in 0...3 ) [for( x in all ) (x.d.s[i] : Float)]];
		var outR = [for( i in 0...3 ) [for( x in all ) hxd.Math.radToDeg(x.d.r[i])]];

		var scaleKeys = [], rotKeys = [];
		for( i in 0...3 ) {
			scaleKeys.push(withScale ? fitKeys(times, outS[i], SCALE_TOLERANCE * Math.max(1, Math.abs(scale[i]))) : null);
			rotKeys.push(fitKeys(times, outR[i], ROTATION_TOLERANCE));
		}
		var fit : Resample = { cs: cs, cr: cr, scale: scale, rot: rot, withScale: withScale, loop: loop, input: input, scaleKeys: scaleKeys, rotKeys: rotKeys,
			problem: null, approx: approx, nonRigid: loss };
		// the keys against the old transform, between the samples and around the keys
		var check = [];
		var t = span.min - 0.5;
		// a re-bake of curves that keep looping holds until its end
		while( t <= span.max + (span.loop && !loop ? 0 : 0.5) ) {
			check.push(t);
			t += SAMPLE_STEP * 0.5;
		}
		for( k in keyTimes ) {
			check.push(k - 1e-4);
			check.push(k + 1e-4);
		}
		// against the closest scale and rotation, the rest is reported as a loss
		var err = fitError(fit, check, (t, out) -> out.load(sampleAt(t, [0., 0., 0.], [1., 1., 1.]).m));
		if( err > MATRIX_TOLERANCE )
			fit.problem = 'rotation the euler angles cannot follow (error ${Math.round(err * 1e4) / 1e4} with sampled keys)';
		return fit;
	}

	/** The worst error of the re-baked keys against the old transform at `times`, relative to the scale of the matrix rows. **/
	function fitError( fit : Resample, times : Array<Float>, oldMatrix : (Float, h3d.Matrix) -> Void ) : Float {
		var ev = new Evaluator();
		function curve( keys : Array<Dynamic>, base : Float ) : Value {
			if( keys == null ) return VConst(base);
			var isBase = keys.length == 1 && Math.abs(keys[0].value - base) <= 1e-12;
			if( isBase ) return VConst(base);
			var d : Dynamic = { type: "curve", name: "c", keyMode: 2, keys: deepCopy(keys) };
			if( fit.loop ) d.loop = true;
			var c : hrt.prefab.Curve = cast @:privateAccess hrt.prefab.Prefab.createFromDynamic(d, null, new hrt.prefab.ContextShared(null, false));
			return c.makeVal();
		}
		var withScale = fit.withScale, scale = fit.scale, rot = fit.rot, sk = fit.scaleKeys, rk = fit.rotKeys;
		var sv = [for( i in 0...3 ) withScale ? curve(sk[i], scale[i]) : VConst(scale[i])];
		var rv = [for( i in 0...3 ) curve(rk[i], rot[i])];
		var a = new h3d.Matrix(), b = new h3d.Matrix();
		var worst = 0.;
		for( t in times ) {
			oldMatrix(t, a);
			if( !withScale ) a.multiply(TransformMath.scaleMatrix(scale), a);
			b.initScale(ev.getFloat(sv[0], t), ev.getFloat(sv[1], t), ev.getFloat(sv[2], t));
			b.rotate(hxd.Math.degToRad(ev.getFloat(rv[0], t)), hxd.Math.degToRad(ev.getFloat(rv[1], t)), hxd.Math.degToRad(ev.getFloat(rv[2], t)));
			var rows = [[a._11, a._12, a._13, b._11, b._12, b._13], [a._21, a._22, a._23, b._21, b._22, b._23], [a._31, a._32, a._33, b._31, b._32, b._33]];
			for( r in rows ) {
				var n = Math.max(1e-6, Math.sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]));
				for( j in 0...3 ) {
					var e = Math.abs(r[j] - r[j + 3]) / Math.max(1, n);
					if( e > worst ) worst = e;
				}
			}
		}
		return worst;
	}

	/** Writes a sampled re-bake, `why` the object has no exact form, warned to list the object **/
	function writeResample( n : RawNode, fit : Resample, why : String ) {
		var withScale = fit.withScale, scale = fit.scale, rot = fit.rot;
		for( i in 0...3 ) {
			if( withScale )
				setChannel(n, fit.cs, "scale", i, fit.scaleKeys[i], scale[i], SCALE_TOLERANCE * Math.max(1, Math.abs(scale[i])), fit.loop, fit.input);
			setChannel(n, fit.cr, "rotation", i, fit.rotKeys[i], rot[i], ROTATION_TOLERANCE, fit.loop, fit.input);
		}
		var msg = '$why: sampled to what the old runtime showed';
		if( fit.input != "" )
			msg += ' over parameter ${fit.input}';
		if( fit.approx != null )
			msg += ', approximated (${fit.approx})';
		if( fit.problem != null )
			msg += ', approximated (${fit.problem})';
		if( fit.nonRigid > MATRIX_TOLERANCE )
			msg += ', the quaternion of the sheared matrix normalized (off by ${Math.round(fit.nonRigid * 1e4) / 1e4})';
		warn(n, msg);
		change(n, withScale ? "rotation and scale, sampled" : "rotation, sampled");
	}

	/** Sets the curve of component `i` of `prop` to `keys` over `input` (see `Resample`), or none when it is the base value. **/
	function setChannel( n : RawNode, ch : Channels, prop : String, i : Int, keys : Array<Dynamic>, base : Float, tol : Float, loop : Bool, input : String ) {
		var isBase = keys.length == 1 && Math.abs(keys[0].value - base) <= tol;
		var cur = ch == null || ch.uniform != null ? null : ch.comps[i];
		if( ch != null && ch.uniform != null && i == 0 ) {
			// the components get their own curves, the uniform one is not read anymore: disable it
			// unless something references it
			var u = ch.uniform;
			if( !users.exists(u) || users.get(u).length == 0 )
				RawNode.setField(u.data, "enabled", false);
			markUpgraded(u);
		}
		if( isBase && cur == null )
			return;
		if( cur != null && users.exists(cur) && users.get(cur).length > 0 ) {
			// keep the shared curve for its users
			for( u in users.get(cur).copy() )
				dereference(u);
		}
		var d : Dynamic = cur != null ? cur.data : newCurve(freeName(n, prop + ":" + COMPONENTS[i]));
		if( isBase )
			keys = [obj(["time", 0., "value", base, "mode", 2])];
		for( f in ["blendMode", "blendParam", "remapPath", "scale", "offset", "loop", "previewKeys", "children"] )
			Reflect.deleteField(d, f);
		RawNode.setField(d, "keyMode", 2);
		RawNode.setField(d, "keys", keys);
		if( loop && !isBase ) RawNode.setField(d, "loop", true);
		if( input != "" && !isBase ) RawNode.setField(d, "remapPath", "$param." + input);
		upgraded.set(d, true);
		if( cur == null )
			n.addChild(d);
		else
			cur.children = [];
	}

	/**
		The object `n` (its old animation has no exact form on its own transform) becomes the only
		child of a new object, which takes its name, its place among its siblings, its position and
		its transform curves: old transform = base scale * base rotation * scale(t) * rotation(t),
		then the position, which is the child (base scale and rotation, no position) under the
		parent (scale(t), rotation(t), position): every curve of the parent is an exact linear bake.
		The object keeps everything else and is renamed `<name>_base`; the paths of the file through
		it are updated.
	**/
	function insertParent( n : RawNode, why : String ) {
		var d = n.data;
		var oldChildren = n.children.copy();
		var parentNode = n.parent;
		var p : Dynamic = obj(["type", "object", "name", d.name]);
		for( f in ["x", "y", "z"] ) {
			var v : Dynamic = get(d, f);
			if( v != null ) {
				Reflect.setField(p, f, v);
				Reflect.deleteField(d, f);
			}
		}
		var animated = [for( c in n.children ) if( isTransformCurve(c) ) c];
		var content = [for( c in n.children ) if( !isTransformCurve(c) ) c];
		var childName = n.name + BASE_SUFFIX;
		var k = 1;
		while( Lambda.exists(animated, c -> c.name == childName) )
			childName = n.name + BASE_SUFFIX + (k++);
		p.children = [d].concat([for( c in animated ) c.data]);
		var dataChildren : Array<Dynamic> = get(d, "children");
		if( dataChildren != null ) {
			for( c in animated ) dataChildren.remove(c.data);
			if( dataChildren.length == 0 ) Reflect.deleteField(d, "children");
		}

		// the tree: the parent takes the place of the object
		var pn = new RawNode();
		pn.data = p;
		pn.type = "object";
		pn.cls = RawNode.classOf("object");
		pn.isCurve = false;
		pn.name = n.name;
		pn.parent = parentNode;
		var arr : Array<Dynamic> = get(parentNode.data, "children");
		arr[arr.indexOf(d)] = p;
		parentNode.children[parentNode.children.indexOf(n)] = pn;
		n.parent = pn;
		n.children = content;
		pn.children = [n].concat(animated);
		for( c in animated ) c.parent = pn;
		n.rename(childName);
		rewritePaths(pn, n, oldChildren);

		// the transform curves of the parent: exact bakes
		var pos = [num(get(p, "x"), 0), num(get(p, "y"), 0), num(get(p, "z"), 0)];
		var gp = group(pn, "position");
		if( anyLegacy(gp) )
			bakeVector(pn, "position", channels(gp, "position", 3), [1, 1, 1], pos, "position");
		var gr = group(pn, "rotation");
		if( anyLegacy(gr) )
			bakeVector(pn, "rotation", channels(gr, "rotation", 3), [360, 360, 360], [0, 0, 0], "rotation, under a parent");
		for( c in group(pn, "scale") ) {
			if( isLegacy(c) ) change(c, "scale, under a parent");
			markUpgraded(c);
		}
		change(pn, "parent object inserted");
		report.parents.push({ path: pn.path(), child: childName, reason: why });
	}

	/**
		The paths of the file that go through the object `child`, now under `parent`: the curve
		references and time remaps (prefab paths from the root), the look at targets and the
		constraints (object paths, see `fixObjectPath`).
	**/
	function rewritePaths( parent : RawNode, child : RawNode, oldChildren : Array<RawNode> ) {
		function fix( path : String ) : String {
			if( path == null ) return null;
			var p = root;
			var out = [];
			for( part in path.split(".") ) {
				// under the parent, a part names one of the old children of the object
				var found = findChild(p == parent ? oldChildren : p.children, part);
				if( found == null ) return path;
				if( p == parent ) {
					if( found.parent == child ) out.push(child.uniqueName());
					out.push(found.uniqueName());
				} else
					out.push(part);
				p = found;
			}
			return out.join(".");
		}
		function walk( n : RawNode ) {
			var d = n.data;
			for( f in (n.isCurve ? ["blendParam", "remapPath"] : ["target", "object"]) ) {
				var v : Dynamic = get(d, f);
				if( !Std.isOfType(v, String) || StringTools.startsWith(v, "$param.") ) continue;
				// the object a constraint moves is the parent, which carries the animation
				var nv = n.isCurve ? fix(v) : fixObjectPath(v, parent, child, !(n.isA(hrt.prefab.l3d.Constraint) && f == "object"));
				if( nv != v ) {
					Reflect.setField(d, f, nv);
					change(n, '$f path through the object moved under a parent');
				}
			}
			for( c in n.children ) walk(c);
		}
		walk(root);
	}

	/**
		An object path (`Prefab.locateObject`: object names from the scene root, the FX object first, a name
		that is not a child searched below) that goes through `parent`, now the parent of `child`, goes through
		`child`; one that names `parent` itself names `child` when `toChild`, the object whose world transform
		is the one of the old object.
	**/
	function fixObjectPath( path : String, parent : RawNode, child : RawNode, toChild : Bool ) : String {
		function search( n : RawNode, name : String ) : RawNode {
			if( n.name == name && !n.isCurve ) return n;
			for( c in n.children ) {
				var f = search(c, name);
				if( f != null ) return f;
			}
			return null;
		}
		var parts = path.split(".");
		var cur : RawNode = null;
		var out = [];
		for( i => part in parts ) {
			var found = cur == null ? search(root, part) : Lambda.find(cur.children, c -> c.name == part && !c.isCurve) ?? search(cur, part);
			if( found == null ) return path;
			out.push(part);
			if( found == parent && (toChild || i < parts.length - 1) ) {
				out.push(child.name);
				found = child;
			}
			cur = found;
		}
		return out.join(".");
	}

	function upgradeObject2D( n : RawNode ) {
		var gp = group(n, "position");
		if( anyLegacy(gp) )
			bakeVector(n, "position", channels(gp, "position", 2), [1, 1], [num(fieldOf(n, "x"), 0), num(fieldOf(n, "y"), 0)], "2d position");
		var gs = group(n, "scale");
		if( anyLegacy(gs) )
			bakeVector(n, "scale", channels(gs, "scale", 2), [num(fieldOf(n, "scaleX"), 1), num(fieldOf(n, "scaleY"), 1)], [0, 0], "2d scale");
		var gr = group(n, "rotation");
		if( anyLegacy(gr) ) {
			// the old code added the rotation of the prefab, in degrees, to the radians of the curve
			var r = num(fieldOf(n, "rotation"), 0);
			bakeVector(n, "rotation", channels(gr, "rotation", 1), [360], [r != 0 ? hxd.Math.radToDeg(r) : 0], r != 0 ? "2d rotation, base read as radians" : "2d rotation");
		}
	}

	/** The last field of the shader `props` named `low` in lower case, the runtime finds the curves case insensitive **/
	static function propName( props : Dynamic, low : String ) : String {
		var name = null;
		if( props != null )
			for( f in Reflect.fields(props) )
				if( f.toLowerCase() == low )
					name = f;
		return name;
	}

	/**
		The value of shader param `name` the old `makeShaderParams` started from: the stored one (`props`),
		else the field of the prefab of that name. Null when there is neither: it was then the default of
		the param in the shader, whose definition is not known here.
	**/
	static function shaderValue( n : RawNode, name : String ) : Dynamic {
		var props : Dynamic = get(n.data, "props");
		var f = propName(props, name.toLowerCase());
		var prop : Dynamic = f == null ? null : Reflect.field(props, f);
		return prop ?? fieldOf(n, f ?? name);
	}

	static function isNumber( v : Dynamic ) return Std.isOfType(v, Float) || Std.isOfType(v, Int);

	function unknownBase( n : RawNode, name : String ) {
		fail(n, 'shader param $name: no stored value nor field, its base value is the default of the param in the shader, which the migration does not know: not upgradable, its curve is kept as the value');
	}

	/**
		A float param was `curve * value` (the value when it is a number, 1 for another value).
		The kind of a param comes from its value: the shader definition is not known.
	**/
	function upgradeShader( n : RawNode ) {
		var seen = new Map();
		for( c in n.children ) {
			if( !c.isCurve || !c.enabled() || !isLegacy(c) ) continue;
			var prefix = c.name.split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) ) continue;
			seen.set(low, true);
			var value : Dynamic = shaderValue(n, prefix);
			if( Std.isOfType(value, Array) )
				continue; // vectors and colors come from their curves
			// the curve of a float: the first enabled one with the name of the param
			var curve = Lambda.find(n.children, x -> x.isCurve && x.enabled() && sameName(x.name, prefix));
			if( curve == null || !isLegacy(curve) ) continue;
			if( value == null ) {
				var hasComponents = Lambda.exists(n.children, x -> x.isCurve && x.enabled() && x.name.indexOf(":") >= 0 && sameName(x.name.split(":")[0], prefix));
				if( !hasComponents )
					unknownBase(curve, prefix);
				continue;
			}
			var k : Float = isNumber(value) ? value : 1;
			bakeLinear(curve, k, 0);
			change(curve, k == 1 ? "shader float, value 1" : "shader float");
		}
	}

	// ----------------------------------------------------------------------------------------
	// Emitters

	static var EMITTER_3D : Array<ParamDef> = [
		{ name: "lifeTime", old: "lifeTime", group: Spawn, def: [1.] },
		{ name: "worldAcceleration", old: "instWorldAcceleration", group: Particle, def: [0., 0., 0.] },
		{ name: "speed", old: "instSpeed", group: Particle, def: [0., 0., 0.] },
		{ name: "worldSpeed", old: "instWorldSpeed", group: Particle, def: [0., 0., 0.] },
		{ name: "startSpeed", old: "instStartSpeed", group: Spawn, def: [0., 0., 0.] },
		{ name: "startWorldSpeed", old: "instStartWorldSpeed", group: Spawn, def: [0., 0., 0.] },
		{ name: "orbitSpeed", old: "instOrbitSpeed", group: Particle, def: [0., 0., 0.] },
		{ name: "orbitSpeedMultiplier", old: "instOrbitSpeedOverTime", group: Multiplier, def: [1.] },
		{ name: "acceleration", old: "instAcceleration", group: Particle, def: [0., 0., 0.] },
		{ name: "maxVelocity", old: "instMaxVelocity", group: Particle, def: [0.] },
		{ name: "dampen", old: "instDampen", group: Particle, def: [0.] },
		{ name: "scale", old: "instScale", group: Particle, def: [1.] },
		{ name: "scaleMultiplier", old: "instScaleOverTime", group: Multiplier, def: [1.] },
		{ name: "stretch", old: "instStretch", group: Particle, def: [1., 1., 1.] },
		{ name: "stretchVelocity", old: "instStretchVelocity", group: Particle, def: [0.] },
		{ name: "rotation", old: "instRotation", group: Particle, def: [0., 0., 0.] },
		{ name: "pivot", old: "instPivot", group: Particle, def: [0., 0., 0.] },
		{ name: "offset", old: "instOffset", group: Particle, def: [0., 0., 0.] },
	];

	static var EMITTER_2D : Array<ParamDef> = [
		{ name: "lifeTime", old: "lifeTime", group: Spawn, def: [1.] },
		{ name: "scale", old: "instScale", group: Particle, def: [1.] },
		{ name: "scaleMultiplier", old: "instScaleOverTime", group: Multiplier, def: [1.] },
		{ name: "stretch", old: "instStretch", group: Particle, def: [1., 1.] },
		{ name: "rotation", old: "instRotation", group: Particle, def: [0.] },
		{ name: "offset", old: "instOffset", group: Particle, def: [0., 0.] },
		{ name: "acceleration", old: "instAcceleration", group: Particle, def: [0., 0.] },
		{ name: "worldAcceleration", old: "instWorldAcceleration", group: Particle, def: [0., 0.] },
		{ name: "speed", old: "instSpeed", group: Particle, def: [0., 0.] },
		{ name: "worldSpeed", old: "instWorldSpeed", group: Particle, def: [0., 0.] },
		{ name: "startSpeed", old: "instStartSpeed", group: Spawn, def: [0., 0.] },
		{ name: "startWorldSpeed", old: "instStartWorldSpeed", group: Spawn, def: [0., 0.] },
		{ name: "orbitSpeed", old: "instOrbitSpeed", group: Particle, def: [0.] },
		{ name: "orbitSpeedMultiplier", old: "instOrbitSpeedOverTime", group: Multiplier, def: [1.] },
		{ name: "maxVelocity", old: "instMaxVelocity", group: Particle, def: [0.] },
		{ name: "dampen", old: "instDampen", group: Particle, def: [0.] },
	];

	/** The emitter settings animated over the FX time, with their default **/
	static var SETTINGS_3D = [{ name: "emitRate", def: 5. }, { name: "emitRateMin", def: 5. }, { name: "emitRateMax", def: 5. },
		{ name: "burstParticleCount", def: 1. }, { name: "emitAngle", def: 30. }];
	static var SETTINGS_2D = [{ name: "burstParticleCount", def: 1. }, { name: "emitRate", def: 5. }, { name: "emitRateMin", def: 5. },
		{ name: "emitRateMax", def: 5. }, { name: "emitRadius", def: 20. }, { name: "emitAngle1", def: 20. }, { name: "emitAngle2", def: 40. },
		{ name: "emitWidth", def: 1. }, { name: "emitHeight", def: 1. }];

	/** The old params added to their curve instead of being multiplied by it **/
	static var ADDITIVE_3D = ["Rotation", "Offset", "Pivot"];
	static var ADDITIVE_2D = ["Rotation", "Offset"];

	static function legacyRand( old : String ) {
		return old == "lifeTime" ? "lifeTimeRand" : old + "_rand";
	}

	function emitterPass( n : RawNode ) {
		if( Migrate.isEmitter(n.data) )
			upgradeEmitter(n);
		for( c in n.children.copy() )
			emitterPass(c);
	}

	function upgradeEmitter( e : RawNode ) {
		var is2D = e.isA(hrt.prefab.fx.Emitter2D);
		var defs = is2D ? EMITTER_2D : EMITTER_3D;
		var props : Dynamic = get(e.data, "props") ?? {};
		var params = upgradeParams(e, props, defs, is2D ? ADDITIVE_2D : ADDITIVE_3D);
		var settings = [for( s in (is2D ? SETTINGS_2D : SETTINGS_3D) ) { name: s.name, value: num(get(props, s.name), s.def) }];
		upgradeEmitterAnims(e, settings, defs, params);

		// orbit speeds in degrees per second
		var orbit = params.get("orbitSpeed");
		if( orbit != null ) {
			var k = 180.0 / Math.PI;
			params.set("orbitSpeed", [for( m in orbit ) switch( m ) {
				case null: null;
				case MConstant(v): MConstant(v * k);
				case MRange(a, b): MRange(a * k, b * k);
				case MCurve(s, f, t): MCurve(s, f * k, t * k);
				case MRandomCurve(s, f0, f1, t0, t1): MRandomCurve(s, f0 * k, f1 * k, t0 * k, t1 * k);
				case MCurveRange(a, af, at, b, bf, bt): MCurveRange(a, af * k, at * k, b, bf * k, bt * k);
			}]);
			change(e, "orbit speed in degrees per second");
		}

		// format 1: the settings are fields of the emitter, the params with modes are in `params`
		var old = new Map();
		for( d in defs ) {
			old.set(d.name, true);
			old.set(d.old, true);
			old.set(legacyRand(d.old), true);
		}
		for( f in Reflect.fields(props) )
			if( !old.exists(f) )
				RawNode.setField(e.data, f, Reflect.field(props, f));
		Reflect.deleteField(e.data, "props");
		var out : Dynamic = {}, any = false;
		for( d in defs ) {
			var v = params.get(d.name);
			var j = v == null ? null : saveValue(v);
			if( j != null ) {
				Reflect.setField(out, d.name, j);
				any = true;
			}
		}
		if( any )
			RawNode.setField(e.data, "params", out);
		change(e, "emitter params with modes");

		// the shaders on its particles
		if( !is2D )
			for( s in particleShaders(e) )
				upgradeParticleShader(s);
	}

	/** The shaders the particles of `e` get (`Shader.getParticleEmitter`) **/
	static function particleShaders( e : RawNode, ?out : Array<RawNode> ) : Array<RawNode> {
		if( out == null ) out = [];
		for( c in e.children ) {
			if( c.isA(hrt.prefab.fx.Emitter) || c.isA(hrt.prefab.l3d.Trails) ) continue;
			if( c.isA(hrt.prefab.Shader) ) out.push(c);
			particleShaders(c, out);
		}
		return out;
	}

	static function isUnset( v : Array<Mode> ) {
		for( m in v ) if( m != null ) return false;
		return true;
	}

	/**
		The old params of an emitter in their modes: the base value `k`, the random amount `a`
		(`_rand`, the value is `k + a * random(-1, 1)`), and curves found by name among the children
		(`instScale`, `instStretch:x`, `instScale:rand`...), first enabled match, case insensitive. A
		curve multiplied the value, or was added to it for the rotation, offset and pivot; a curve in
		RandomBlend mode replaced it by a random between its two child curves.
	**/
	function upgradeParams( e : RawNode, props : Dynamic, defs : Array<ParamDef>, additive : Array<String> ) : Map<String, Array<Mode>> {
		var params = new Map<String, Array<Mode>>();
		// the life time was already a plain value
		var life : Dynamic = get(props, "lifeTime");
		if( Std.isOfType(life, Float) || Std.isOfType(life, Int) )
			params.set("lifeTime", [MConstant(life)]);
		inline function findCurve( name : String ) : RawNode {
			return Lambda.find(e.children, c -> c.isCurve && c.enabled() && sameName(c.name, name));
		}
		for( d in defs ) {
			var old = d.old;
			var baseField : Dynamic = old != d.name ? get(props, old) : null;
			var randField : Dynamic = get(props, legacyRand(old));
			var dim = d.def.length;
			var cur = params.get(d.name);
			var out : Array<Mode> = [for( i in 0...dim ) cur == null ? null : cur[i]];
			var changed = false;
			for( i in 0...dim ) {
				var suffix = dim == 1 ? "" : ":" + COMPONENTS[i];
				// the old code reads the arrays as Float, a missing element is 0
				inline function comp( v : Dynamic ) : Null<Float> {
					return v == null ? null : dim == 1 ? (Std.isOfType(v, Array) ? null : num(v, 0)) : (Std.isOfType(v, Array) ? num((v : Array<Dynamic>)[i], 0) : null);
				}
				var base = comp(baseField);
				if( d.name == "lifeTime" && out[i] != null )
					base = switch( out[i] ) { case MConstant(v): v; default: base; };
				var rand = comp(randField);
				var hasRand = rand != null && rand != 0;
				var k = base ?? d.def[i];
				var ci = findCurve(old + suffix);
				var ri = findCurve(old + suffix + ":rand");
				var isBlend = ci != null && blendMode(ci) == 2;
				var mode : Mode = null;
				if( d.group != Particle ) {
					// the curves of these params are animation curves over the FX time (`upgradeEmitterAnims`)
					if( ri != null )
						warn(e, '${old + suffix}:rand: a random curve on a ${d.group == Spawn ? "Spawn" : "Multiplier"} param has no equivalent, ignored');
					if( hasRand && d.group == Spawn )
						mode = MRange(k - rand, k + rand);
					else {
						if( hasRand )
							warn(e, '${d.name}: random amount $rand ignored, a multiplier is a constant');
						if( base != null || hasRand )
							mode = MConstant(k);
					}
				} else {
					var isAdditive = Lambda.exists(additive, a -> old.indexOf(a) >= 0);
					var curve = ci?.uniqueName();
					if( ri != null && ci == null ) {
						// the random amount follows a curve: k + a * random * curve(t)
						var a = rand ?? 1.0;
						mode = MRandomCurve(ri.uniqueName(), k, k, k - a, k + a);
					} else {
						if( ri != null )
							warn(e, '${old + suffix}:rand: a random curve next to a curve has no equivalent, ignored');
						if( isBlend ) {
							// lerp(curve0(t), curve1(t), random), the base and random amount are not used
							var sub = ci.children;
							if( sub.length < 2 || !sub[0].isCurve || !sub[1].isCurve )
								warn(e, '${old + suffix}: random blend without its two child curves');
							else if( !sub[0].enabled() || !sub[1].enabled() )
								warn(e, '${old + suffix}: disabled child curve of a random blend');
							inline function path( j : Int ) return ci.uniqueName() + "." + (j < sub.length ? sub[j].uniqueName() : "0");
							mode = MCurveRange(path(0), 0, 1, path(1), 0, 1);
						} else if( curve != null ) {
							if( isAdditive )
								mode = hasRand ? MRandomCurve(curve, k - rand, k + rand, k - rand + 1, k + rand + 1) : MCurve(curve, k, k + 1);
							else
								mode = hasRand ? MRandomCurve(curve, 0, 0, k - rand, k + rand) : MCurve(curve, 0, k);
						} else if( hasRand )
							mode = MRange(k - rand, k + rand);
						else if( base != null )
							mode = MConstant(k);
					}
				}
				if( mode != null || baseField != null || randField != null ) {
					out[i] = mode;
					changed = true;
				}
			}
			if( changed ) {
				if( isUnset(out) )
					params.remove(d.name);
				else
					params.set(d.name, out);
			}
		}
		return params;
	}

	/**
		The old animation curves of an emitter: the settings (`settings`, with their value), the spawn
		params and the multipliers were multiplied by their curve, found by name (the old names). The
		curves are baked and named after what they animate (`EmitterParam.animKey`). A range
		`(k ± a) * curve` gets one curve per bound (the second one a reference to the first).
	**/
	function upgradeEmitterAnims( e : RawNode, settings : Array<{ name : String, value : Float }>, defs : Array<ParamDef>,
		params : Map<String, Array<Mode>> ) {
		inline function find( name : String ) : RawNode {
			return Lambda.find(e.children, c -> c.isCurve && c.enabled() && sameName(c.name, name));
		}
		inline function isBlend( n : RawNode ) return blendMode(n) == 2;
		var renames = [];

		// emitter settings: value * curve
		for( s in settings ) {
			var n = find(s.name);
			if( n == null || !isLegacy(n) ) continue;
			if( !isBlend(n) )
				bakeLinear(n, s.value, 0);
			change(n, isBlend(n) ? "emitter setting, random blend" : "emitter setting");
		}

		// spawn params and multipliers
		for( d in defs ) {
			if( d.group == Particle || d.name == "lifeTime" ) continue;
			var dim = d.def.length;
			var value = params.get(d.name);
			var out : Array<Mode> = [for( i in 0...dim ) value == null ? null : value[i]];
			var changed = false;
			for( i in 0...dim ) {
				var suffix = dim == 1 ? "" : ":" + COMPONENTS[i];
				var key = d.name + suffix;
				var m = out[i];
				var bounds = switch( m ) { case MRange(lo, hi): { lo: lo, hi: hi }; case null, _: null; };
				var k = switch( m ) { case MConstant(v): v; case null, _: d.def[i]; };
				var c = find(d.old + suffix);
				if( c == null || !isLegacy(c) ) continue;
				if( d.group == Multiplier ) {
					renames.push({ node: c, name: key });
					if( !isBlend(c) ) bakeLinear(c, k, 0);
					change(c, isBlend(c) ? "multiplier, random blend" : "multiplier");
					continue;
				}
				if( isBlend(c) ) {
					// random between the two child curves, the value is not used
					if( c.curveChildren().length < 2 ) {
						warn(c, "random blend without its two child curves");
						continue;
					}
					if( m != null ) {
						out[i] = null;
						changed = true;
					}
					renames.push({ node: c, name: key });
					change(c, "spawn, random blend");
					continue;
				}
				if( bounds == null ) {
					renames.push({ node: c, name: key });
					bakeLinear(c, k, 0);
					change(c, "spawn value");
					continue;
				}
				// (k ± a) * c: one curve per bound
				var lo = bounds.lo, hi = bounds.hi;
				if( hi != 0 ) {
					renames.push({ node: c, name: key + ":max" });
					// a reference to `c`, compensated by the bake of `c`
					if( lo != 0 )
						linearCopy(c, e, key + ":min", lo, 0);
					bakeLinear(c, hi, 0);
				} else if( lo != 0 ) {
					renames.push({ node: c, name: key + ":min" });
					bakeLinear(c, lo, 0);
				}
				change(c, "spawn range");
			}
			if( changed ) {
				if( isUnset(out) )
					params.remove(d.name);
				else
					params.set(d.name, out);
			}
		}
		renameCurves(renames);
		markAll(e, e, false);
	}

	/** Renames curves, the paths of the file to them or through them follow **/
	function renameCurves( renames : Array<{ node : RawNode, name : String }> ) {
		if( renames.length == 0 )
			return;
		var refs = [];
		function collect( n : RawNode ) {
			if( n.isCurve )
				for( f in (blendMode(n) == 3 ? ["blendParam", "remapPath"] : ["remapPath"]) ) {
					var v : Dynamic = get(n.data, f);
					var target = Std.isOfType(v, String) ? locate(v) : null;
					if( target != null )
						refs.push({ node: n, field: f, target: target });
				}
			for( c in n.children )
				collect(c);
		}
		collect(root);
		for( r in renames ) {
			if( Lambda.exists(r.node.parent.children, c -> c != r.node && c.enabled() && sameName(c.name, r.name)) )
				warn(r.node, 'renamed ${r.name}, the name of another curve');
			r.node.rename(r.name);
		}
		for( r in refs ) {
			var path = pathOf(r.target);
			if( path != null && path != get(r.node.data, r.field) ) {
				Reflect.setField(r.node.data, r.field, path);
				change(r.node, r.field + " path to a renamed curve");
			}
		}
	}

	/**
		The curves of a shader under an emitter, evaluated over the particle life. The shader definition
		is not known, the kind of a param comes from its stored value: a float was `curve * value`, a
		vector came from its component curves alone, 0 for the others (1 for w). Colors keep their curves.
	**/
	function upgradeParticleShader( s : RawNode ) {
		var props : Dynamic = get(s.data, "props");
		var out = new Map<String, Array<Mode>>();
		var seen = new Map();
		for( c in s.children ) {
			if( !c.enabled() || !c.isCurve ) continue;
			var prefix = c.name.split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) ) continue;
			seen.set(low, true);
			// the runtime finds the curves from the shader var name, case insensitive
			var name = propName(props, low) ?? prefix;
			var prop : Dynamic = shaderValue(s, name);
			var group = [for( x in s.children ) if( x.enabled() && x.isCurve && sameName(x.name.split(":")[0], name) ) x];
			var components = Lambda.exists(group, x -> x.name.indexOf(":") >= 0);
			var isVector = Std.isOfType(prop, Array) || (prop == null && components);
			if( isVector && low.indexOf("color") >= 0 )
				continue;
			if( isVector ) {
				var dim = Std.isOfType(prop, Array) ? hxd.Math.imin((prop : Array<Dynamic>).length, 4) : 4;
				var v : Array<Mode> = [];
				// a component without curve was 0 (1 for w): its prop
				var base : Array<Dynamic> = [for( k in 0...dim ) Std.isOfType(prop, Array) ? (prop : Array<Dynamic>)[k] : 0.];
				for( k in 0...dim ) {
					var suffix = ":" + COMPONENTS[k];
					var x = Lambda.find(group, x -> StringTools.endsWith(x.name.toLowerCase(), suffix));
					v.push(x != null ? MCurve(x.uniqueName(), 0, 1) : null);
					if( x == null ) base[k] = k == 3 ? 1. : 0.;
				}
				if( props == null ) RawNode.setField(s.data, "props", props = {});
				Reflect.setField(props, name, base);
				out.set(name, v);
			} else {
				var x = Lambda.find(s.children, x -> x.isCurve && x.enabled() && sameName(x.name, name));
				// component curves on a float are not read
				if( x == null )
					continue;
				// the old code multiplied by the value when it is a number, by 1 otherwise
				if( prop == null )
					unknownBase(x, name);
				out.set(name, [MCurve(x.uniqueName(), 0, isNumber(prop) ? num(prop, 0) : 1.0)]);
			}
		}
		if( !out.iterator().hasNext() )
			return;
		var names = [for( k in out.keys() ) k];
		names.sort(Reflect.compare);
		function comp( m : Mode ) : Dynamic {
			return switch( m ) {
			case MCurve(path, from, to): obj(["curve", path, "from", from, "to", to]);
			case null, _: null;
			}
		}
		RawNode.setField(s.data, "particleParams", [for( n in names ) obj(["name", n, "comps", [for( m in out.get(n) ) comp(m)]])]);
		change(s, "particle shader params with modes");
	}

	// Format 1 of the modes, `EmitterParam.saveMode`: a constant is a plain number, the other modes an object with a `mode` field, a vector an object of its components.

	static function saveValue( v : Array<Mode> ) : Dynamic {
		if( v == null || isUnset(v) )
			return null;
		if( v.length == 1 )
			return saveMode(v[0]);
		var o : Dynamic = {};
		for( i => m in v )
			if( m != null )
				Reflect.setField(o, COMPONENTS[i], saveMode(m));
		return o;
	}

	static function saveMode( m : Mode ) : Dynamic {
		inline function span( o : Dynamic, from : Float, to : Float ) {
			if( from != 0 ) o.from = from;
			if( to != 1 ) o.to = to;
		}
		function shape( fields : Array<Dynamic>, path : String ) : Dynamic {
			return obj(fields.concat(["curve", path]));
		}
		return switch( m ) {
		case null: null;
		case MConstant(v): v;
		case MRange(min, max): obj(["mode", "Range", "min", min, "max", max]);
		case MCurve(s, from, to):
			var o : Dynamic = shape(["mode", "Curve"], s);
			span(o, from, to);
			o;
		case MRandomCurve(s, f0, f1, t0, t1):
			var o : Dynamic = shape(["mode", "RandomCurve"], s);
			if( f0 != 0 || f1 != 0 ) o.from = obj(["min", f0, "max", f1]);
			if( t0 != 1 || t1 != 1 ) o.to = obj(["min", t0, "max", t1]);
			o;
		case MCurveRange(a, af, at, b, bf, bt):
			var oa : Dynamic = shape([], a), ob : Dynamic = shape([], b);
			span(oa, af, at);
			span(ob, bf, bt);
			obj(["mode", "CurveRange", "a", oa, "b", ob]);
		}
	}

	// ----------------------------------------------------------------------------------------
	// References

	function referencePass( n : RawNode ) {
		if( n.isA(hrt.prefab.Reference) )
			upgradeReference(n);
		for( c in n.children )
			referencePass(c);
	}

	/**
		The overrides of a reference were made for the file it references in version 0: they are
		applied on that file, the result upgraded, and the overrides made again from the upgraded
		file to it. Kept as they are when they still give the same result.
	**/
	function upgradeReference( n : RawNode ) {
		var source : String = get(n.data, "source");
		var overrides : Dynamic = get(n.data, "overrides");
		if( source == null || overrides == null )
			return;
		var raw = ctx.readRaw(source);
		if( raw == null ) {
			warn(n, 'overrides of $source, which cannot be read: kept as they are');
			return;
		}
		// the file is already migrated (a project migrated in part), or has nothing to migrate
		if( Migrate.versionOf(raw) != 0 )
			return;
		var upgradedSource = ctx.migrated(source);
		if( upgradedSource == null ) {
			warn(n, 'overrides of $source, which cannot be upgraded: kept as they are');
			return;
		}
		if( haxe.Json.stringify(upgradedSource) == haxe.Json.stringify(raw) )
			return;
		var merged = hrt.prefab.Diff.apply(deepCopy(raw), deepCopy(overrides));
		var target = ctx.upgradeAs(merged, source);
		var same = hrt.prefab.Diff.apply(deepCopy(upgradedSource), deepCopy(overrides));
		if( haxe.Json.stringify(same) == haxe.Json.stringify(target) )
			return;
		switch( hrt.prefab.Diff.diffPrefab(upgradedSource, target) ) {
		case Skip:
			Reflect.deleteField(n.data, "overrides");
		case Set(d):
			Reflect.setField(n.data, "overrides", d);
		}
		change(n, 'overrides of $source made for its upgrade');
	}
}
