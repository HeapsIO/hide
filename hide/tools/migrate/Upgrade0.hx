package hide.tools.migrate;

import hide.tools.migrate.Migrate.FileReport;
import hide.tools.migrate.RawNode.get;
import hrt.prefab.Diff.deepCopy;

/** A component of a vector property after the upgrade: `a * old[src] + b`, the value of the prefab when `src` is null **/
private typedef ChannelMap = { src : Null<Int>, a : Float, b : Float };

/** The curves of a vector property: `uniform` when one curve is all of them **/
private typedef Channels = { uniform : Null<RawNode>, comps : Array<Null<RawNode>> };

/** The mode of a param component (format 1), `shape` the path of a curve from the emitter **/
private enum Mode {
	MConstant( v : Float );
	MRange( min : Float, max : Float );
	MCurve( shape : String, from : Float, to : Float );
	MRandomCurve( shape : String, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
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
	  (its components permuted). An object whose animation has no such form (a rotation the euler
	  curves cannot follow, a scale the base rotation shears) gets a parent object, which takes its
	  name, its place, its position and its animation as it is; it keeps its base rotation and scale
	  and its content, under a new name (`<name>_base`). The paths of the file through it are updated.
	  An object that reads its parent object, sets its own rotation or is read by its parent through its
	  direct children keeps an approximation (`noParent`).
	- The overrides of the references are rewritten for the upgraded files they override (see
	  `upgradeReference`), reading the other files of the project through the context.

	It writes the data of format 1.
**/
@:access(hide.tools.migrate.Migrate)
class Upgrade0 {

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
	var fileRoot : Bool;

	public function new( ctx : Null<Migrate.Context>, report : FileReport ) {
		this.ctx = ctx;
		this.file = report.file;
		this.report = report;
	}

	/**
		Upgrades in place `data`, the root of FX data (an FX, an emitter out of any FX), `fileRoot` when it
		is the root of its file (the paths of the curve references start there, they are not written otherwise).
	**/
	public function run( data : Dynamic, fileRoot : Bool ) {
		root = RawNode.build(data, null, []);
		this.fileRoot = fileRoot;
		indexUsers(root);
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

	function change( node : RawNode, kind : String ) {
		report.changes.push({ path: node.path(), kind: kind });
	}

	function isLegacy( n : RawNode ) return n.isCurve && !upgraded.exists(n.data);
	function anyLegacy( g : Array<RawNode> ) return Lambda.exists(g, c -> isLegacy(c));
	function markUpgraded( n : RawNode ) upgraded.set(n.data, true);

	// ----------------------------------------------------------------------------------------
	// Paths

	/** The child of `n` at `part` of a path, like `Prefab.locatePrefab`: the exact name first, else `name-N` for the Nth of that name **/
	static function findChild( children : Array<RawNode>, part : String ) : Null<RawNode> {
		var found = Lambda.find(children, c -> c.name == part);
		var dash = part.lastIndexOf("-");
		if( found == null && dash > 0 ) {
			var name = part.substr(0, dash), nth = Std.parseInt(part.substr(dash + 1)) ?? 0;
			found = Lambda.find(children, c -> c.name == name && nth-- == 0);
		}
		return found;
	}

	/** Like `Prefab.locatePrefab` from `base`, the root of the file by default **/
	function locate( path : String, ?base : RawNode ) : Null<RawNode> {
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
	function pathOf( node : RawNode ) : Null<String> {
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
	// FX

	/** The outermost FX of the file get their animations upgraded. **/
	function fxPass( n : RawNode ) {
		var is2D = n.isA(hrt.prefab.fx.FX2D);
		if( n.isA(hrt.prefab.fx.FX) || is2D ) {
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
	static function particleEmitter( n : RawNode ) : Null<RawNode> {
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

	/** Like `FXAnimation.vectorAnimation`: the curve of each component, `uniform` when one curve is all of them. **/
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
		var pos = [num(get(d, "x"), 0), num(get(d, "y"), 0), num(get(d, "z"), 0)];
		var scale = [num(get(d, "scaleX"), 1), num(get(d, "scaleY"), 1), num(get(d, "scaleZ"), 1)];
		var rot = [num(get(d, "rotationX"), 0), num(get(d, "rotationY"), 0), num(get(d, "rotationZ"), 0)];


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
		var problem = cs != null && scaleMap == null ? "scale through the base rotation (shear)" : cr != null && form == null ? "rotation the euler angles cannot follow" : null;
		if( problem != null ) {
			var kept = noParent(n);
			if( kept == null ) {
				insertParent(n, problem);
				return;
			}
			warn(n, '$problem, $kept: approximated');
			if( scaleMap == null && cs != null ) {
				var perm = TransformMath.nearestScalePermutation(rot);
				scaleMap = [for( i in 0...3 ) { src: cs.comps[perm[i]] == null ? null : perm[i], a: scale[i], b: 0. }];
			}
			if( form == null && cr != null ) form = { base: rot, perm: [0, 1, 2], sign: [1., 1., 1.] };
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
	function noParent( n : RawNode ) : Null<String> {
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
		constraints (object paths, made of the same names).
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
				var nv = fix(v);
				if( nv != v ) {
					Reflect.setField(d, f, nv);
					change(n, '$f path through the object moved under a parent');
				}
			}
			for( c in n.children ) walk(c);
		}
		walk(root);
	}

	function upgradeObject2D( n : RawNode ) {
		var d = n.data;
		var gp = group(n, "position");
		if( anyLegacy(gp) )
			bakeVector(n, "position", channels(gp, "position", 2), [1, 1], [num(get(d, "x"), 0), num(get(d, "y"), 0)], "2d position");
		var gs = group(n, "scale");
		if( anyLegacy(gs) )
			bakeVector(n, "scale", channels(gs, "scale", 2), [num(get(d, "scaleX"), 1), num(get(d, "scaleY"), 1)], [0, 0], "2d scale");
		var gr = group(n, "rotation");
		if( anyLegacy(gr) ) {
			// the old code added the rotation of the prefab, in degrees, to the radians of the curve
			var r = num(get(d, "rotation"), 0);
			bakeVector(n, "rotation", channels(gr, "rotation", 1), [360], [r != 0 ? hxd.Math.radToDeg(r) : 0], r != 0 ? "2d rotation, base read as radians" : "2d rotation");
		}
	}

	/** The last field of the shader `props` named `low` in lower case, the runtime finds the curves case insensitive **/
	static function propName( props : Dynamic, low : String ) : Null<String> {
		var name = null;
		if( props != null )
			for( f in Reflect.fields(props) )
				if( f.toLowerCase() == low )
					name = f;
		return name;
	}

	/**
		A float param was `curve * value` (the stored value when it is a number, 1 for another value).
		The kind of a param comes from its stored value: the shader definition is not known.
	**/
	function upgradeShader( n : RawNode ) {
		var props : Dynamic = get(n.data, "props");
		var seen = new Map();
		for( c in n.children ) {
			if( !c.isCurve || !c.enabled() || !isLegacy(c) ) continue;
			var prefix = c.name.split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) ) continue;
			seen.set(low, true);
			var f = propName(props, low);
			var prop : Dynamic = f == null ? null : Reflect.field(props, f), found = f != null;
			if( Std.isOfType(prop, Array) )
				continue; // vectors and colors come from their curves
			// the curve of a float: the first enabled one with the name of the param
			var curve = Lambda.find(n.children, x -> x.isCurve && x.enabled() && sameName(x.name, prefix));
			if( curve == null || !isLegacy(curve) ) continue;
			if( !found ) {
				var hasComponents = Lambda.exists(n.children, x -> x.isCurve && x.enabled() && x.name.indexOf(":") >= 0 && sameName(x.name.split(":")[0], prefix));
				if( hasComponents ) continue;
				warn(curve, "shader param without a stored value, taken as a float of default 0");
				bakeLinear(curve, 0, 0);
				change(curve, "shader float, no value");
				continue;
			}
			var isNumber = Std.isOfType(prop, Float) || Std.isOfType(prop, Int);
			if( !isNumber ) continue;
			var k : Float = prop;
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

	static function isUnset( v : Array<Null<Mode>> ) {
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
	function upgradeParams( e : RawNode, props : Dynamic, defs : Array<ParamDef>, additive : Array<String> ) : Map<String, Array<Null<Mode>>> {
		var params = new Map<String, Array<Null<Mode>>>();
		// the life time was already a plain value
		var life : Dynamic = get(props, "lifeTime");
		if( Std.isOfType(life, Float) || Std.isOfType(life, Int) )
			params.set("lifeTime", [MConstant(life)]);
		inline function findCurve( name : String ) : Null<RawNode> {
			return Lambda.find(e.children, c -> c.isCurve && c.enabled() && sameName(c.name, name));
		}
		for( d in defs ) {
			var old = d.old;
			var baseField : Dynamic = old != d.name ? get(props, old) : null;
			var randField : Dynamic = get(props, legacyRand(old));
			var dim = d.def.length;
			var cur = params.get(d.name);
			var out : Array<Null<Mode>> = [for( i in 0...dim ) cur == null ? null : cur[i]];
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
				var mode : Null<Mode> = null;
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
					var curve = ci == null ? null : ci.uniqueName();
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
		params : Map<String, Array<Null<Mode>>> ) {
		inline function find( name : String ) : Null<RawNode> {
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
			var out : Array<Null<Mode>> = [for( i in 0...dim ) value == null ? null : value[i]];
			var changed = false;
			for( i in 0...dim ) {
				var suffix = dim == 1 ? "" : ":" + COMPONENTS[i];
				var key = d.name + suffix;
				var m = out[i];
				var bounds = switch( m ) { case MRange(lo, hi): { lo: lo, hi: hi }; default: null; };
				var k = switch( m ) { case MConstant(v): v; default: d.def[i]; };
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
		var out = new Map<String, Array<Null<Mode>>>();
		var seen = new Map();
		for( c in s.children ) {
			if( !c.enabled() || !c.isCurve ) continue;
			var prefix = c.name.split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) ) continue;
			seen.set(low, true);
			// the runtime finds the curves from the shader var name, case insensitive
			var name = propName(props, low) ?? prefix;
			var prop : Dynamic = props == null ? null : Reflect.field(props, name);
			var group = [for( x in s.children ) if( x.enabled() && x.isCurve && sameName(x.name.split(":")[0], name) ) x];
			var components = Lambda.exists(group, x -> x.name.indexOf(":") >= 0);
			var isVector = Std.isOfType(prop, Array) || (prop == null && components);
			if( isVector && low.indexOf("color") >= 0 )
				continue;
			if( isVector ) {
				var dim = Std.isOfType(prop, Array) ? hxd.Math.imin((prop : Array<Dynamic>).length, 4) : 4;
				var v : Array<Null<Mode>> = [];
				for( k in 0...dim ) {
					var suffix = ":" + COMPONENTS[k];
					var x = Lambda.find(group, x -> StringTools.endsWith(x.name.toLowerCase(), suffix));
					v.push(x != null ? MCurve(x.uniqueName(), 0, 1) : MConstant(k == 3 ? 1 : 0));
				}
				out.set(name, v);
			} else {
				var x = Lambda.find(s.children, x -> x.isCurve && x.enabled() && sameName(x.name, name));
				// component curves on a float are not read
				if( x == null )
					continue;
				// the old code multiplied by the value when it is a number, by 1 otherwise, and a missing
				// value is the default of the param: 0 for a float
				var isNumber = Std.isOfType(prop, Float) || Std.isOfType(prop, Int);
				var base = isNumber ? num(prop, 0) : prop != null ? 1.0 : 0.0;
				if( prop == null )
					warn(s, '$name: no stored value, taken as a float of default 0');
				out.set(name, [MCurve(x.uniqueName(), 0, base)]);
			}
		}
		if( !out.iterator().hasNext() )
			return;
		var names = [for( k in out.keys() ) k];
		names.sort(Reflect.compare);
		var params : Dynamic = {};
		for( n in names )
			Reflect.setField(params, n, saveValue(out.get(n)));
		RawNode.setField(s.data, "particleParams", params);
		change(s, "particle shader params with modes");
	}

	// Format 1 of the modes, `EmitterParam.save`: a constant is a plain number, the other modes an object with a `mode` field.

	static function saveValue( v : Array<Null<Mode>> ) : Dynamic {
		if( v == null || isUnset(v) )
			return null;
		if( v.length == 1 )
			return saveMode(v[0]);
		return [for( m in v ) saveMode(m)];
	}

	static function saveMode( m : Null<Mode> ) : Dynamic {
		inline function span( o : Dynamic, from : Float, to : Float ) {
			if( from != 0 ) o.from = from;
			if( to != 1 ) o.to = to;
		}
		return switch( m ) {
		case null: null;
		case MConstant(v): v;
		case MRange(min, max): obj(["mode", "Range", "min", min, "max", max]);
		case MCurve(s, from, to):
			var o : Dynamic = obj(["mode", "Curve", "curve", s]);
			span(o, from, to);
			o;
		case MRandomCurve(s, f0, f1, t0, t1):
			var o : Dynamic = obj(["mode", "RandomCurve", "curve", s]);
			if( f0 != 0 || f1 != 0 ) o.from = obj(["min", f0, "max", f1]);
			if( t0 != 1 || t1 != 1 ) o.to = obj(["min", t0, "max", t1]);
			o;
		case MCurveRange(a, af, at, b, bf, bt):
			var oa : Dynamic = obj(["curve", a]), ob : Dynamic = obj(["curve", b]);
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
