package hrt.prefab.fx;

import hrt.prefab.Curve;
import hrt.prefab.fx.EmitterParam;

/** A prefab of the raw (json) data of a prefab tree, before it is loaded. **/
@:allow(hrt.prefab.fx.AnimUpgrade)
class RawNode {
	public var data : Dynamic;
	public var parent : RawNode;
	public var children : Array<RawNode> = [];
	/** The name the prefab gets once loaded **/
	public var name : String;
	public var cls : Null<Class<Prefab>>;
	public var isCurve : Bool;

	function new() {}

	public function isA( cl : Class<Prefab> ) {
		return cls != null && Prefab.isOfType(cls, cl);
	}

	/** A curve saved before `Curve.VERSION`: its values are in the old format. **/
	public function isLegacy() {
		return isCurve && (Reflect.field(data, "version") == null || Reflect.field(data, "version") == 0);
	}

	public function enabled() {
		return Reflect.field(data, "enabled") != false;
	}

	/** Like `Prefab.getUniqueName`: `name-N` for the Nth sibling of the same name. **/
	public function uniqueName() {
		if( parent == null )
			return "";
		var n = 0;
		for( c in parent.children ) {
			if( c == this ) break;
			if( c.name == name ) n++;
		}
		return n > 0 ? name + "-" + n : name;
	}

	public function curveChildren() {
		return [for( c in children ) if( c.isCurve ) c];
	}
}

/**
	Upgrade of the animation curves (curves over the FX time) saved before `Curve.VERSION`.
	Old format only, nothing else should depend on it.

	The old FX composed the curves with the property they animate: a shader float, an emitter
	setting, a spawn param and a multiplier were multiplied by their curve, a position was offset
	by it, a scale and a rotation (in turns) were applied over the transform of the object.
	An animation curve now holds the value of the property. The upgrade bakes the old constants
	into the curves:

	- linear cases (`a * curve + b`) are exact: the key values and handles are scaled and shifted,
	  a Reference curve takes them in its own scale / offset, a Blend curve bakes its two children;
	  the curves that reference a baked curve are compensated (their scale / offset), so they keep
	  reading the same values.
	- the rotation and scale of an object composed with a base rotation are not linear: the old
	  transform is sampled over the time span of the curves and fitted with linear keys.

	The upgrade works on the raw data, from the `load` of the FX (before its children exist) and
	of the emitters. A curve is upgraded once: it is saved with its `version`.
**/
/** A component of a vector property after the upgrade: `a * old[src] + b`, the value of the prefab when `src` is null **/
private typedef ChannelMap = { src : Null<Int>, a : Float, b : Float };

class AnimUpgrade {

	/** Called for old data the upgrade can only approximate. **/
	public static dynamic function onWarning( path : String, message : String ) {
	}

	/** Called for each upgraded property, `kind` tells how (for statistics). **/
	public static dynamic function onUpgrade( path : String, kind : String ) {
	}

	/** Disables the upgrade (used to load the legacy data as it is). **/
	public static var enabled = true;

	/** Rotation tolerance of the sampled re-bakes, in degrees **/
	public static var ROTATION_TOLERANCE = 0.01;
	/** Scale tolerance of the sampled re-bakes, relative **/
	public static var SCALE_TOLERANCE = 1e-5;
	/** Sampling step of the re-bakes, in seconds **/
	public static var SAMPLE_STEP = 1.0 / 240.0;

	// ----------------------------------------------------------------------------------------
	// Raw tree

	static function classOf( type : String ) : Null<Class<Prefab>> {
		if( type == null ) return null;
		var info = @:privateAccess Prefab.getPrefabInfoByName(type);
		return info?.prefabClass;
	}

	static function build( data : Dynamic, parent : RawNode ) : RawNode {
		var n = new RawNode();
		n.data = data;
		n.parent = parent;
		n.cls = classOf(get(data, "type"));
		n.isCurve = n.cls != null && Prefab.isOfType(n.cls, Curve);
		var name : String = get(data, "name") ?? "";
		n.name = n.isCurve ? Curve.loadedName(name, parent != null && parent.isCurve ? parent.name : null) : name;
		var children : Array<Dynamic> = get(data, "children");
		if( children != null )
			for( c in children )
				if( c != null )
					n.children.push(build(c, n));
		return n;
	}

	static function hasLegacy( data : Dynamic ) : Bool {
		if( data == null ) return false;
		if( get(data, "type") == "curve" && (get(data, "version") == null || get(data, "version") == 0) )
			return true;
		var children : Array<Dynamic> = get(data, "children");
		if( children != null )
			for( c in children )
				if( hasLegacy(c) ) return true;
		return false;
	}

	/** A field of raw data (a direct access can read a missing number as 0 on HL) **/
	static inline function get( d : Dynamic, f : String ) : Dynamic {
		return Reflect.field(d, f);
	}

	/** The value a missing field of a curve key (or handle) loads with, see `CurveKey` **/
	static inline var CurveKeyDefault = -1.0;

	static function num( v : Dynamic, def : Float ) : Float {
		return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : def;
	}

	static function newCurve( name : String ) : Dynamic {
		return { type: "curve", name: name, version: Curve.VERSION, keyMode: 2, keys: [] };
	}

	static function addChild( parent : RawNode, data : Dynamic ) : RawNode {
		var children : Array<Dynamic> = get(parent.data, "children");
		if( children == null )
			parent.data.children = children = [];
		children.push(data);
		var n = build(data, parent);
		parent.children.push(n);
		return n;
	}

	/** A name no enabled sibling has (the curves are found by name among the enabled ones) **/
	static function freeName( parent : RawNode, name : String ) {
		var n = name, i = 1;
		while( Lambda.exists(parent.children, c -> c.enabled() && Curve.sameName(c.name, n)) )
			n = name + "_" + (i++);
		return n;
	}

	static function deepCopy( v : Dynamic ) : Dynamic {
		return hrt.prefab.Diff.deepCopy(v);
	}

	// ----------------------------------------------------------------------------------------
	// Curve operations

	/** The context of the upgrade of a whole tree: the reference users of the curves. **/
	var root : RawNode;
	var users : Map<RawNode, Array<RawNode>> = new Map();
	var remapUsers : Map<RawNode, Array<RawNode>> = new Map();
	var parameters : Map<String, Float> = new Map();
	var fxDuration : Float = 0;
	var pristine : Dynamic;
	var mirror : Prefab;
	var mirrorNodes : Map<RawNode, Prefab>;
	var pathPrefix : String;

	function new() {}

	/** Like `Prefab.locatePrefab` from the root of the tree. **/
	function locate( path : String ) : Null<RawNode> {
		if( path == null || root == null )
			return null;
		var p = root;
		for( part in path.split(".") ) {
			var sub = part.split("-");
			var nth = 0;
			var name = part;
			if( sub.length > 1 ) {
				nth = Std.parseInt(sub.pop()) ?? 0;
				name = sub[0];
			}
			var found = null;
			for( c in p.children )
				if( c.name == name ) {
					if( nth-- == 0 ) {
						found = c;
						break;
					}
				}
			if( found == null )
				return null;
			p = found;
		}
		return p;
	}

	/** The path of `node` from the root (`locate`), null if it cannot be written as one. **/
	function pathOf( node : RawNode ) : Null<String> {
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

	static function warn( node : RawNode, msg : String ) {
		onWarning(nodePath(node), msg);
	}

	static function nodePath( node : RawNode ) {
		var parts = [];
		var p = node;
		while( p != null && p.parent != null ) {
			parts.unshift(p.name);
			p = p.parent;
		}
		return parts.join(".");
	}

	function indexUsers( n : RawNode ) {
		if( n.isCurve ) {
			var bm = blendMode(n);
			if( bm == 3 ) {
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

	static function blendMode( n : RawNode ) : Int {
		var b : Dynamic = get(n.data, "blendMode");
		if( b == null ) return 0;
		return Std.isOfType(b, Int) ? b : Std.parseInt(Std.string(b)) ?? 0;
	}

	/** Copies the data of `from` into the curve `to` (a reference user), which stops depending on it. **/
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
		Reflect.deleteField(copy, "version");
		for( f in Reflect.fields(user.data) )
			Reflect.deleteField(user.data, f);
		for( f in Reflect.fields(copy) )
			Reflect.setField(user.data, f, Reflect.field(copy, f));
		users.get(target)?.remove(user);
		var rebuilt = build(user.data, user.parent);
		user.children = rebuilt.children;
		for( c in user.children ) c.parent = user;
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
				u.data.scale = s / a;
				u.data.offset = o - b * s / a;
			}
		if( compensate && remapUsers.exists(n) )
			warn(n, "curve used as the time remap of other curves, they read the upgraded values");
		var d = n.data;
		switch( blendMode(n) ) {
		case 3:
			d.scale = num(get(d, "scale"), 1) * a;
			d.offset = num(get(d, "offset"), 0) * a + b;
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
				keys = d.keys = [{ time: 0., value: 0., mode: mode }, { time: 1., value: 1., mode: mode }];
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
			var n = addChild(parent, d);
			var us = users.get(src);
			if( us == null ) users.set(src, us = []);
			us.push(n);
			return n;
		}
		var d : Dynamic = deepCopy(src.data);
		d.name = freeName(parent, name);
		var n = addChild(parent, d);
		indexUsers(n);
		bakeLinear(n, a, b, false);
		return n;
	}

	/** Marks the old curves as upgraded. The curves of the emitters are left to them (`upgradeEmitter`), but the root. **/
	function markAll( n : RawNode, skipEmitters : Bool ) {
		if( n.parent != null && n.isCurve && isEmitter(n.parent) && (skipEmitters || n.parent != root) )
			return;
		if( n.isCurve && n.isLegacy() )
			n.data.version = Curve.VERSION;
		for( c in n.children )
			markAll(c, skipEmitters);
	}

	static function isEmitter( n : RawNode ) {
		return n.isA(hrt.prefab.fx.Emitter) || n.isA(hrt.prefab.fx.Emitter2D);
	}

	// ----------------------------------------------------------------------------------------
	// Legacy evaluation (sampled re-bakes)

	/** The tree loaded as plain prefabs with its curves, in the old format, to evaluate them. **/
	function getMirror( n : RawNode ) : Prefab {
		if( mirror == null ) {
			mirrorNodes = new Map();
			function strip( d : Dynamic ) : Dynamic {
				if( get(d, "type") == "curve" ) return deepCopy(d);
				var o : Dynamic = { name: d.name };
				var ch : Array<Dynamic> = get(d, "children");
				if( ch != null ) o.children = [for( c in ch ) if( c != null ) strip(c)];
				return o;
			}
			var prev = enabled;
			enabled = false;
			mirror = @:privateAccess Prefab.createFromDynamic(strip(pristine), null, new ContextShared(null, false));
			enabled = prev;
			function map( r : RawNode, p : Prefab ) {
				mirrorNodes.set(r, p);
				for( i in 0...r.children.length )
					if( i < p.children.length )
						map(r.children[i], p.children[i]);
			}
			map(root, mirror);
		}
		return mirrorNodes.get(n);
	}

	/** Keys of a curve and of what it depends on, for the time span of a re-bake. **/
	function collectSpan( n : RawNode, span : { min : Float, max : Float, loop : Bool, param : Bool }, ?keyTimes : Array<Float>, depth = 0 ) {
		if( n == null || depth > 16 ) return;
		var d = n.data;
		if( get(d, "loop") == true ) span.loop = true;
		var remap : String = get(d, "remapPath");
		if( remap != null ) {
			if( StringTools.startsWith(remap, "$param.") ) span.param = true;
			else {
				// the curve is read at the remapped time, the span is the one of the remap curve
				var r = locate(remap);
				collectSpan(r, span, keyTimes, depth + 1);
				return;
			}
		}
		switch( blendMode(n) ) {
		case 3: collectSpan(locate(get(d, "blendParam")), span, keyTimes, depth + 1);
		case 1:
			span.param = true;
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

	/** Linear keys fitting `values` (sampled at `times`) within `tol`. **/
	static function fitKeys( times : Array<Float>, values : Array<Float>, tol : Float ) : Array<Dynamic> {
		var n = times.length;
		var keep = [for( _ in 0...n ) false];
		keep[0] = keep[n - 1] = true;
		var stack = [0, n - 1];
		while( stack.length > 0 ) {
			var b = stack.pop(), a = stack.pop();
			var worst = -1, err = tol;
			for( i in a + 1...b ) {
				var f = (times[i] - times[a]) / (times[b] - times[a]);
				var e = Math.abs(values[a] + (values[b] - values[a]) * f - values[i]);
				if( e > err ) {
					err = e;
					worst = i;
				}
			}
			if( worst >= 0 ) {
				keep[worst] = true;
				stack.push(a); stack.push(worst);
				stack.push(worst); stack.push(b);
			}
		}
		var keys = [];
		for( i in 0...n )
			if( keep[i] )
				keys.push({ time: times[i], value: values[i], mode: 2 });
		// a constant curve is one key
		if( keys.length == 2 && Math.abs(keys[0].value - keys[1].value) <= tol )
			keys.pop();
		return keys;
	}

	// ----------------------------------------------------------------------------------------
	// FX tree

	/**
		Upgrades the old animation curves of the FX whose raw data is `data`, in place. Called from
		`FX.load` / `FX2D.load`. The curves under the emitters are upgraded by them (`upgradeEmitter`),
		except the ones that animate the emitter object.
	**/
	public static function upgradeFX( data : Dynamic, is2D : Bool ) {
		if( !enabled || !hasLegacy(data) )
			return;
		var u = new AnimUpgrade();
		u.pristine = deepCopy(data);
		u.root = build(data, null);
		var params : Array<Dynamic> = get(data, "parameters");
		if( params != null )
			for( p in params )
				u.parameters.set(get(p, "name"), num(get(p, "def"), 0));
		// the default duration of an FX
		u.fxDuration = num(get(data, "duration"), 5.0);
		u.indexUsers(u.root);
		u.prepareEmitters(u.root);
		u.process(u.root, is2D, false);
		u.markAll(u.root, true);
	}

	/**
		The emitters upgrade their own curves later, from their load: the curves that reference the
		ones they bake are made independent first (they would read the new values otherwise).
	**/
	function prepareEmitters( n : RawNode ) {
		if( isEmitter(n) ) {
			for( c in n.children )
				if( c.isLegacy() && isEmitterAnim(c.name) ) {
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
		if( !is2D && !inEmitter && n.isA(Object3D) )
			upgradeObject3D(n);
		if( is2D && n.isA(Object2D) )
			upgradeObject2D(n);
		if( (n.isA(Shader) && !isParticleShader(n)) || n.isA(hrt.prefab.rfx.ScreenShaderGraph) )
			upgradeShader(n);
		var em = n.isA(hrt.prefab.fx.Emitter);
		for( c in n.children )
			process(c, is2D, inEmitter || em);
	}

	/** Mirrors `Shader.getParticleEmitter`: the shaders under an emitter are evaluated over the particle life. **/
	static function isParticleShader( n : RawNode ) {
		var p = n.parent;
		while( p != null ) {
			if( p.isA(hrt.prefab.fx.Emitter) ) return true;
			if( p.isA(hrt.prefab.l3d.Trails) ) return false;
			p = p.parent;
		}
		return false;
	}

	/** The enabled curves named `name` or `name:...`, like `Curve.getCurves` **/
	static function group( n : RawNode, name : String ) : Array<RawNode> {
		return [for( c in n.children ) if( c.isCurve && c.enabled() && Curve.sameName(c.name.split(":")[0], name) ) c];
	}

	/** Like `FXAnimation.vectorCurves`: the curve of each component, `uniform` when one curve is all of them. **/
	static function channels( curves : Array<RawNode>, name : String, dim : Int ) : { uniform : Null<RawNode>, comps : Array<Null<RawNode>> } {
		if( curves.length == 1 && curves[0].name == name )
			return { uniform: curves[0], comps: [for( _ in 0...dim ) curves[0]] };
		return { uniform: null, comps: [for( i in 0...dim ) {
			var suffix = ":" + EmitterParam.COMPONENTS[i];
			Lambda.find(curves, c -> StringTools.endsWith(c.name.toLowerCase(), suffix));
		}] };
	}

	static var AXES = ["X", "Y", "Z"];

	/**
		Applies `a[i] * value + b[i]` to the curves of a vector property. A curve shared by several
		components (`uniform`) with different factors is split into one reference per component.
	**/
	function bakeVector( owner : RawNode, prop : String, ch : { uniform : Null<RawNode>, comps : Array<Null<RawNode>> }, a : Array<Float>, b : Array<Float>, kind : String ) {
		var u = ch.uniform;
		if( u != null ) {
			if( !u.isLegacy() ) return;
			var same = true;
			for( i in 1...a.length )
				if( a[i] != a[0] || b[i] != b[0] ) same = false;
			if( same ) {
				bakeLinear(u, a[0], b[0]);
				onUpgrade(nodePath(u), kind + ", uniform");
			} else {
				// the uniform curve stays as the shape of its components
				for( i in 0...a.length )
					linearCopy(u, owner, prop + ":" + EmitterParam.COMPONENTS[i], a[i], b[i]);
				onUpgrade(nodePath(u), kind + ", uniform split");
			}
			return;
		}
		for( i in 0...a.length ) {
			var c = ch.comps[i];
			if( c == null || !c.isLegacy() ) continue;
			bakeLinear(c, a[i], b[i]);
			onUpgrade(nodePath(c), kind);
		}
	}

	function upgradeObject3D( n : RawNode ) {
		var d = n.data;
		var pos = [num(get(d, "x"), 0), num(get(d, "y"), 0), num(get(d, "z"), 0)];
		var scale = [num(get(d, "scaleX"), 1), num(get(d, "scaleY"), 1), num(get(d, "scaleZ"), 1)];
		var rot = [num(get(d, "rotationX"), 0), num(get(d, "rotationY"), 0), num(get(d, "rotationZ"), 0)];

		inline function anyLegacy( g : Array<RawNode> ) return Lambda.exists(g, c -> c.isLegacy());

		// position: offset of the base position
		var gp = group(n, "position");
		if( anyLegacy(gp) )
			bakeVector(n, "position", channels(gp, "position", 3), [1, 1, 1], pos, "position");

		// local position / rotation: offsets of the leaves, the rotation is now in degrees
		var glr = group(n, "localRotation");
		if( anyLegacy(glr) )
			bakeVector(n, "localRotation", channels(glr, "localRotation", 3), [360, 360, 360], [0, 0, 0], "local rotation");

		var gs = group(n, "scale"), gr = group(n, "rotation");
		if( !anyLegacy(gs) && !anyLegacy(gr) )
			return;
		var cs = gs.length == 0 ? null : channels(gs, "scale", 3);
		var cr = gr.length == 0 ? null : channels(gr, "rotation", 3);

		// old transform: base scale * base rotation * scale(t) * rotation(t) (row vectors, the base first)
		var rb = new h3d.Matrix();
		rb.initRotation(hxd.Math.degToRad(rot[0]), hxd.Math.degToRad(rot[1]), hxd.Math.degToRad(rot[2]));
		var rbm = [[rb._11, rb._12, rb._13], [rb._21, rb._22, rb._23], [rb._31, rb._32, rb._33]];

		// the animated scale moves before the base rotation: base rotation * scale(t) = scale'(t) * base rotation
		var scaleMap : Array<ChannelMap> = null;
		if( cs != null ) {
			// commutes when the components mixed by the base rotation are the same curve
			var commutes = cs.uniform != null;
			if( !commutes ) {
				commutes = true;
				for( i in 0...3 ) for( j in 0...3 )
					if( i != j && Math.abs(rbm[i][j]) > 1e-9 && cs.comps[i] != cs.comps[j] )
						commutes = false;
			}
			if( commutes )
				scaleMap = [for( i in 0...3 ) { src: cs.comps[i] == null ? null : i, a: scale[i], b: 0. }];
			else {
				// a base rotation by quarter turns permutes the components
				var perm = [for( i in 0...3 ) -1];
				for( i in 0...3 ) for( j in 0...3 )
					if( Math.abs(Math.abs(rbm[i][j]) - 1) < 1e-9 ) perm[i] = j;
				if( perm.indexOf(-1) < 0 )
					scaleMap = [for( i in 0...3 ) { src: cs.comps[perm[i]] == null ? null : perm[i], a: scale[i], b: 0. }];
			}
		}

		// base rotation * rotation(t) as euler angles linear in the curves
		var rotMap : Array<ChannelMap> = null;
		if( cr != null ) {
			var animAxes = [for( i in 0...3 ) if( cr.comps[i] != null ) i];
			var maxBase = -1, minAnim = 3;
			for( i in 0...3 ) if( rot[i] != 0 ) maxBase = i;
			for( i in animAxes ) if( i < minAnim ) minAnim = i;
			if( maxBase <= minAnim ) // Rx Ry Rz (base) * Rx Ry Rz (anim): one rotation in that order
				rotMap = [for( i in 0...3 ) cr.comps[i] == null ? { src: null, a: 0., b: rot[i] } : { src: i, a: 360., b: rot[i] }];
			else if( animAxes.length == 1 && cr.uniform == null ) {
				// one animated axis: the rotation of one euler angle when it goes through the base rotation
				var k = animAxes[0];
				for( j in 0...3 ) for( sg in [1., -1.] ) {
					if( rotMap != null ) break;
					if( rotationMatches(rot, k, j, sg) )
						rotMap = [for( i in 0...3 ) i == j ? { src: k, a: 360. * sg, b: rot[i] } : { src: null, a: 0., b: rot[i] }];
				}
			}
		}

		var mixed = (anyLegacy(gs) && Lambda.exists(gs, c -> !c.isLegacy())) || (anyLegacy(gr) && Lambda.exists(gr, c -> !c.isLegacy()));
		var exactScale = cs == null || scaleMap != null;
		var exactRot = cr == null || rotMap != null;
		if( mixed && !(exactScale && exactRot) ) {
			warn(n, "rotation / scale curves upgraded in part only, the others are kept");
			return;
		}
		if( !exactScale ) {
			resample(n, cs, cr, scale, rot, true);
			return;
		}
		if( !exactRot )
			resample(n, null, cr, scale, rot, false);
		if( cr != null && rotMap != null && anyLegacy(gr) )
			applyMap(n, "rotation", cr, rotMap, rot[0] == 0 && rot[1] == 0 && rot[2] == 0 ? "rotation" : "rotation, base rotation folded");
		if( cs != null && anyLegacy(gs) )
			applyMap(n, "scale", cs, scaleMap, cr == null ? "scale" : "scale, with rotation");
	}

	/** Whether base rotation * R_k(a) is the euler angles `rot` with `s * a` added to angle `j`, for any `a`. **/
	static function rotationMatches( rot : Array<Float>, k : Int, j : Int, s : Float ) {
		var m1 = new h3d.Matrix(), m2 = new h3d.Matrix(), r = new h3d.Matrix();
		for( a in [0.37, 1.3, 2.9, -2.2] ) {
			var b = [for( v in rot ) hxd.Math.degToRad(v)];
			m1.initRotation(b[0], b[1], b[2]);
			r.initRotation(k == 0 ? a : 0, k == 1 ? a : 0, k == 2 ? a : 0);
			m1.multiply(m1, r);
			b[j] += s * a;
			m2.initRotation(b[0], b[1], b[2]);
			for( e in [m1._11 - m2._11, m1._12 - m2._12, m1._13 - m2._13, m1._21 - m2._21, m1._22 - m2._22, m1._23 - m2._23, m1._31 - m2._31, m1._32 - m2._32, m1._33 - m2._33] )
				if( Math.abs(e) > 1e-9 ) return false;
		}
		return true;
	}

	/**
		Sets the curves of a vector property from the old ones: component `i` becomes `a * old[src] + b`,
		or the value of the prefab (`b`, no curve) when `src` is null.
	**/
	function applyMap( owner : RawNode, prop : String, ch : { uniform : Null<RawNode>, comps : Array<Null<RawNode>> }, map : Array<ChannelMap>, kind : String ) {
		var u = ch.uniform;
		if( u != null ) {
			if( !u.isLegacy() ) return;
			var same = true;
			for( m in map ) if( m.src == null || m.a != map[0].a || m.b != map[0].b ) same = false;
			if( same ) {
				bakeLinear(u, map[0].a, map[0].b);
				onUpgrade(nodePath(u), kind + ", uniform");
				return;
			}
			// the uniform curve stays as the shape of its components
			var any = false;
			for( i in 0...map.length )
				if( map[i].src != null ) {
					linearCopy(u, owner, prop + ":" + EmitterParam.COMPONENTS[i], map[i].a, map[i].b);
					any = true;
				}
			if( !any && (!users.exists(u) || users.get(u).length == 0) ) u.data.enabled = false;
			onUpgrade(nodePath(u), kind + ", uniform split");
			return;
		}
		var orig = [for( c in ch.comps ) c == null ? null : deepCopy(c.data)];
		for( i in 0...map.length ) {
			var m = map[i];
			var node = ch.comps[i];
			if( m.src == i ) {
				if( node.isLegacy() ) {
					bakeLinear(node, m.a, m.b);
					onUpgrade(nodePath(node), kind);
				}
				continue;
			}
			if( m.src == null ) {
				// the value of the prefab: the curve is not read anymore
				if( node != null && node.isLegacy() ) {
					node.data.enabled = false;
					onUpgrade(nodePath(node), kind + ", moved to another component");
				}
				continue;
			}
			// another component: a copy of its old curve
			var d : Dynamic = deepCopy(orig[m.src]);
			d.name = node != null ? node.data.name : freeName(owner, prop + ":" + EmitterParam.COMPONENTS[i]);
			if( node != null )
				d.enabled = node.data.enabled;
			Reflect.deleteField(d, "version");
			var target = node;
			if( target == null )
				target = addChild(owner, d);
			else
				replaceData(target, d);
			indexUsers(target);
			bakeLinear(target, m.a, m.b, false);
			onUpgrade(nodePath(target), kind + ", from another component");
		}
	}

	/** Replaces the data of a curve, the curves that referenced it get its old data. **/
	function replaceData( node : RawNode, d : Dynamic ) {
		var us = users.get(node);
		if( us != null )
			for( u in us.copy() ) dereference(u);
		for( f in Reflect.fields(node.data) )
			Reflect.deleteField(node.data, f);
		for( f in Reflect.fields(d) )
			Reflect.setField(node.data, f, Reflect.field(d, f));
		var rebuilt = build(node.data, node.parent);
		node.children = rebuilt.children;
		for( c in node.children ) c.parent = node;
	}

	/**
		Re-bakes the rotation (and the scale when `withScale`) of an object by sampling its old transform:
		the components that vary get a curve of linear keys, the old curves are rewritten (the shared ones
		are left to their reference users).
	**/
	function resample( n : RawNode, cs : Null<{ uniform : Null<RawNode>, comps : Array<Null<RawNode>> }>, cr : Null<{ uniform : Null<RawNode>, comps : Array<Null<RawNode>> }>,
		scale : Array<Float>, rot : Array<Float>, withScale : Bool ) {
		var involved : Array<RawNode> = [];
		for( ch in [cs, cr] )
			if( ch != null )
				for( c in ch.comps )
					if( c != null && involved.indexOf(c) < 0 )
						involved.push(c);
		var span = { min: 0., max: 0., loop: false, param: false };
		var keyTimes = [];
		var periods = [];
		var varyingOnce = false;
		for( c in involved ) {
			var cspan = { min: 0., max: 0., loop: false, param: false };
			collectSpan(c, cspan, keyTimes);
			if( cspan.min < span.min ) span.min = cspan.min;
			if( cspan.max > span.max ) span.max = cspan.max;
			if( cspan.param ) span.param = true;
			if( cspan.loop ) {
				span.loop = true;
				if( periods.indexOf(cspan.max) < 0 ) periods.push(cspan.max);
			} else if( !isConstant(c) )
				varyingOnce = true;
		}
		if( span.param )
			warn(n, "rotation / scale curve depending on an FX parameter, re-baked for its default value");
		// all the curves loop on the same period: so does the re-bake
		var loop = span.loop && !varyingOnce && periods.length == 1 && span.min >= 0 && periods[0] > 0;
		if( loop ) {
			span.min = 0;
			span.max = periods[0];
		} else {
			var duration = fxDuration > 0 ? fxDuration : 5.0;
			if( span.loop && span.max < duration ) span.max = duration;
			span.max += 1;
			if( span.loop )
				warn(n, "looping rotation / scale curves re-baked up to the end of the FX");
		}

		getMirror(n);
		var ev = new Evaluator();
		for( k => v in parameters ) ev.parameters.set(k, v);
		function val( c : Null<RawNode> ) : Null<Value> {
			if( c == null ) return null;
			var p = Std.downcast(mirrorNodes.get(c), Curve);
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
		var m = new h3d.Matrix();
		var outS = [[], [], []], outR = [[], [], []];
		var prev = [for( r in rot ) hxd.Math.degToRad(r)];
		var worst = 0.;
		for( t in times ) {
			inline function f( v : Null<Value>, def : Float ) return v == null ? def : ev.getFloat(v, t);
			var s = withScale ? [f(sv[0], 1), f(sv[1], 1), f(sv[2], 1)] : [1., 1., 1.];
			m.initScale(s[0], s[1], s[2]);
			m.rotate(f(rv[0], 0) * Math.PI * 2, f(rv[1], 0) * Math.PI * 2, f(rv[2], 0) * Math.PI * 2);
			m.multiply(base, m);
			var d = decompose(m, prev, withScale ? [s[0] * scale[0], s[1] * scale[1], s[2] * scale[2]] : [1., 1., 1.]);
			prev = d.r;
			for( i in 0...3 ) {
				outS[i].push(d.s[i]);
				outR[i].push(hxd.Math.radToDeg(d.r[i]));
			}
			if( d.error > worst ) worst = d.error;
		}
		if( worst > 1e-4 )
			warn(n, 'scale and rotation not separable (shear ${Math.round(worst * 1e4) / 1e4}), approximated');

		for( i in 0...3 ) {
			if( withScale ) {
				var stol = SCALE_TOLERANCE * Math.max(1, Math.abs(scale[i]));
				setChannel(n, cs, "scale", i, fitKeys(times, outS[i], stol), scale[i], stol, loop);
			}
			setChannel(n, cr, "rotation", i, fitKeys(times, outR[i], ROTATION_TOLERANCE), rot[i], ROTATION_TOLERANCE, loop);
		}
		onUpgrade(nodePath(n), withScale ? "rotation and scale, sampled" : "rotation, sampled");
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

	/** Sets the curve of component `i` of `prop` to `keys`, or none when it is the base value. **/
	function setChannel( n : RawNode, ch : Null<{ uniform : Null<RawNode>, comps : Array<Null<RawNode>> }>, prop : String, i : Int, keys : Array<Dynamic>, base : Float, tol : Float, loop : Bool ) {
		var isBase = keys.length == 1 && Math.abs(keys[0].value - base) <= tol;
		var cur = ch == null || ch.uniform != null ? null : ch.comps[i];
		if( ch != null && ch.uniform != null && i == 0 ) {
			// the components get their own curves, the uniform one is not read anymore: disable it
			// unless something references it
			var u = ch.uniform;
			if( !users.exists(u) || users.get(u).length == 0 )
				u.data.enabled = false;
		}
		if( isBase && cur == null )
			return;
		if( cur != null && users.exists(cur) && users.get(cur).length > 0 ) {
			// keep the shared curve for its users
			for( u in users.get(cur).copy() )
				dereference(u);
		}
		var d : Dynamic = cur != null ? cur.data : newCurve(freeName(n, prop + ":" + EmitterParam.COMPONENTS[i]));
		if( isBase )
			keys = [{ time: 0., value: base, mode: 2 }];
		for( f in ["blendMode", "blendParam", "remapPath", "scale", "offset", "loop", "previewKeys"] )
			Reflect.deleteField(d, f);
		d.keyMode = 2;
		d.keys = keys;
		if( loop && !isBase ) d.loop = true;
		Reflect.deleteField(d, "children");
		d.version = Curve.VERSION;
		if( cur == null )
			addChild(n, d);
		else
			cur.children = [];
	}

	/**
		Scale and euler angles (radians, closest to `prev`) of a matrix (its 3x3 part), `signs` telling
		the sign of each scale. `error`: what the rebuilt matrix misses of it.
	**/
	static function decompose( m : h3d.Matrix, prev : Array<Float>, signs : Array<Float> ) : { s : Array<Float>, r : Array<Float>, error : Float } {
		var rows = [[m._11, m._12, m._13], [m._21, m._22, m._23], [m._31, m._32, m._33]];
		var det = m._11 * (m._22 * m._33 - m._23 * m._32) - m._12 * (m._21 * m._33 - m._23 * m._31) + m._13 * (m._21 * m._32 - m._22 * m._31);
		var sg = [for( v in signs ) v < 0 ? -1. : 1.];
		if( (sg[0] * sg[1] * sg[2] < 0) != (det < 0) )
			sg = [-sg[0], -sg[1], -sg[2]];
		var s = [for( i in 0...3 ) sg[i] * Math.sqrt(rows[i][0] * rows[i][0] + rows[i][1] * rows[i][1] + rows[i][2] * rows[i][2])];
		var r = [for( i in 0...3 ) [for( j in 0...3 ) s[i] == 0 ? (i == j ? 1. : 0.) : rows[i][j] / s[i]]];
		inline function closest( a : Float, ref : Float ) {
			var tau = Math.PI * 2;
			return a + Math.round((ref - a) / tau) * tau;
		}
		var cands = [];
		var cy = Math.sqrt(r[0][0] * r[0][0] + r[0][1] * r[0][1]);
		if( cy > 1e-6 ) {
			var y = Math.atan2(-r[0][2], cy);
			cands.push([Math.atan2(r[1][2], r[2][2]), y, Math.atan2(r[0][1], r[0][0])]);
			cands.push([Math.atan2(-r[1][2], -r[2][2]), Math.PI - y, Math.atan2(-r[0][1], -r[0][0])]);
		} else {
			var z = prev[2];
			if( -r[0][2] > 0 ) // y = 90
				cands.push([z + Math.atan2(r[1][0], r[1][1]), Math.PI / 2, z]);
			else
				cands.push([Math.atan2(-r[1][0], r[1][1]) - z, -Math.PI / 2, z]);
		}
		var best = null, bestD = Math.POSITIVE_INFINITY;
		for( c in cands ) {
			var a = [for( i in 0...3 ) closest(c[i], prev[i])];
			var dist = 0.;
			for( i in 0...3 ) dist += (a[i] - prev[i]) * (a[i] - prev[i]);
			if( dist < bestD ) {
				bestD = dist;
				best = a;
			}
		}
		// error of the rebuilt matrix
		var check = new h3d.Matrix();
		check.initScale(s[0], s[1], s[2]);
		check.rotate(best[0], best[1], best[2]);
		var err = 0.;
		var scaleRef = Math.max(1e-6, Math.max(Math.abs(s[0]), Math.max(Math.abs(s[1]), Math.abs(s[2]))));
		for( e in [check._11 - m._11, check._12 - m._12, check._13 - m._13, check._21 - m._21, check._22 - m._22, check._23 - m._23, check._31 - m._31, check._32 - m._32, check._33 - m._33] )
			err = Math.max(err, Math.abs(e) / scaleRef);
		return { s: s, r: best, error: err };
	}

	function upgradeObject2D( n : RawNode ) {
		var d = n.data;
		inline function anyLegacy( g : Array<RawNode> ) return Lambda.exists(g, c -> c.isLegacy());
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

	/**
		A float param was `curve * value` (the stored value when it is a number, 1 for another value).
		The kind of a param comes from its stored value: the shader definition is not known at load.
	**/
	function upgradeShader( n : RawNode ) {
		var props : Dynamic = get(n.data, "props");
		var seen = new Map();
		for( c in n.children ) {
			if( !c.isCurve || !c.enabled() || !c.isLegacy() ) continue;
			var prefix = c.name.split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) ) continue;
			seen.set(low, true);
			var prop : Dynamic = null, found = false;
			if( props != null )
				for( f in Reflect.fields(props) )
					if( f.toLowerCase() == low ) {
						prop = Reflect.field(props, f);
						found = true;
					}
			if( Std.isOfType(prop, Array) )
				continue; // vectors and colors come from their curves
			// the curve of a float: the first enabled one with the name of the param
			var curve = Lambda.find(n.children, x -> x.isCurve && x.enabled() && Curve.sameName(x.name, prefix));
			if( curve == null || !curve.isLegacy() ) continue;
			if( !found ) {
				var hasComponents = Lambda.exists(n.children, x -> x.isCurve && x.enabled() && x.name.indexOf(":") >= 0 && Curve.sameName(x.name.split(":")[0], prefix));
				if( hasComponents ) continue;
				warn(curve, "shader param without a stored value, taken as a float of default 0");
				bakeLinear(curve, 0, 0);
				onUpgrade(nodePath(curve), "shader float, no value");
				continue;
			}
			var isNumber = Std.isOfType(prop, Float) || Std.isOfType(prop, Int);
			if( !isNumber ) continue;
			var k : Float = prop;
			bakeLinear(curve, k, 0);
			onUpgrade(nodePath(curve), k == 1 ? "shader float, value 1" : "shader float");
		}
	}

	// ----------------------------------------------------------------------------------------
	// Emitters

	/**
		Upgrades the old animation curves of an emitter, from its load (raw children, params already
		in their modes): the emitter settings (`settings`, with their value), the spawn params and the
		multipliers were multiplied by their curve, found by name (the old names, see
		`EmitterUpgrade.LEGACY_NAMES`). The curves are bound to the params by path in `anim` and
		baked. A range `(k ± a) * curve` gets one curve per bound (the second one a reference to the
		first). Returns the components that need an unused random slot before their own.
	**/
	public static function upgradeEmitter( owner : Prefab, rawChildren : Array<Dynamic>, settings : Array<{ name : String, value : Float }>,
		defs : Array<ModeParamDef>, params : Map<String, ParamValue>, anim : AnimCurves ) : Array<String> {
		if( !enabled || rawChildren == null )
			return null;
		var hasOld = false;
		for( c in rawChildren ) if( hasLegacy(c) ) hasOld = true;
		if( !hasOld )
			return null;

		var u = new AnimUpgrade();
		// the emitter as the root of its children, the paths of `anim` are relative to it
		u.root = build({ name: owner.name, children: rawChildren }, null);
		u.root.cls = Type.getClass(owner);
		u.pathPrefix = owner.getAbsPath(true);
		u.indexUsers(u.root);
		var skips = [];
		var path = (n : RawNode) -> {
			var parts = [];
			var p = n;
			while( p != u.root ) {
				parts.unshift(p.uniqueName());
				p = p.parent;
			}
			return parts.join(".");
		};
		inline function resolve( key : String ) : Null<RawNode> {
			var p = anim.get(key);
			return p == null ? null : u.locateRel(p);
		}
		inline function find( name : String ) : Null<RawNode> {
			return Lambda.find(u.root.children, c -> c.isCurve && c.enabled() && Curve.sameName(c.name, name));
		}
		inline function isBlend( n : RawNode ) return blendMode(n) == 2;

		// emitter settings: value * curve
		for( s in settings ) {
			var n = resolve(s.name);
			if( n == null ) {
				n = find(s.name);
				if( n == null || !n.isLegacy() ) continue;
				anim.set(s.name, path(n));
			}
			if( !n.isLegacy() ) continue;
			if( !isBlend(n) )
				u.bakeLinear(n, s.value, 0);
			onUpgrade(nodePath(n), isBlend(n) ? "emitter setting, random blend" : "emitter setting");
		}

		// spawn params and multipliers
		for( d in defs ) {
			if( d.animated != true || d.name == "lifeTime" ) continue;
			var old = EmitterUpgrade.LEGACY_NAMES.get(d.name);
			var dim = d.def.length;
			var value = params.get(d.name);
			var out : ParamValue = [for( i in 0...dim ) value == null ? null : value[i]];
			var changed = false;
			for( i in 0...dim ) {
				var suffix = dim == 1 ? "" : ":" + EmitterParam.COMPONENTS[i];
				var key = dim == 1 ? d.name : d.name + "." + EmitterParam.COMPONENTS[i];
				var m = out[i];
				var kValue = EmitterParam.paramAnimKey(d, i), kMin = EmitterParam.paramAnimKey(d, i, "min"), kMax = EmitterParam.paramAnimKey(d, i, "max");
				var bounds = switch( m ) { case MRange(lo, hi): { lo: lo, hi: hi }; default: null; };
				var k = switch( m ) { case MConstant(v): v; case null: d.def[i]; default: d.def[i]; };

				// already bound (an old override can bring old values back on a bound curve)
				var bv = resolve(kValue), bmin = resolve(kMin), bmax = resolve(kMax);
				if( bv != null || bmin != null || bmax != null ) {
					if( bv != null && bv.isLegacy() && !isBlend(bv) ) u.bakeLinear(bv, k, 0);
					if( bounds != null ) {
						if( bmin != null && bmin.isLegacy() && !isBlend(bmin) && blendMode(bmin) != 3 ) u.bakeLinear(bmin, bounds.lo, 0);
						if( bmax != null && bmax.isLegacy() && !isBlend(bmax) ) u.bakeLinear(bmax, bounds.hi, 0);
					}
					continue;
				}

				var c = find(old + suffix);
				if( c == null || !c.isLegacy() ) continue;
				var cpath = path(c);
				if( d.group == Multiplier ) {
					anim.set(kValue, cpath);
					if( !isBlend(c) ) u.bakeLinear(c, k, 0);
					onUpgrade(nodePath(c), isBlend(c) ? "multiplier, random blend" : "multiplier");
					continue;
				}
				if( isBlend(c) ) {
					// random between the two child curves: a range between them, the value is not used
					var sub = c.curveChildren();
					if( sub.length < 2 ) {
						warn(c, "random blend without its two child curves");
						continue;
					}
					if( bounds == null ) {
						out[i] = MRange(k, k);
						changed = true;
					} else if( skips.indexOf(key) < 0 )
						skips.push(key); // the random amount took a slot before the one of the blend
					anim.set(kMin, path(sub[0]));
					anim.set(kMax, path(sub[1]));
					onUpgrade(nodePath(c), "spawn, random blend");
					continue;
				}
				if( bounds == null ) {
					anim.set(kValue, cpath);
					u.bakeLinear(c, k, 0);
					onUpgrade(nodePath(c), "spawn value");
					continue;
				}
				// (k ± a) * c: one curve per bound
				var lo = bounds.lo, hi = bounds.hi;
				if( hi != 0 ) {
					anim.set(kMax, cpath);
					if( lo != 0 ) {
						var ref = u.linearCopyRel(c, d.name + suffix + ":min", lo / hi, lo, owner);
						anim.set(kMin, path(ref));
					}
					u.bakeLinear(c, hi, 0);
				} else if( lo != 0 ) {
					anim.set(kMin, cpath);
					u.bakeLinear(c, lo, 0);
				}
				onUpgrade(nodePath(c), "spawn range");
			}
			if( changed )
				params.set(d.name, out);
		}
		u.markAll(u.root, false);
		return skips.length > 0 ? skips : null;
	}

	/** `locate` relative to the root, without the `-` parsing of `locatePrefab` (paths of `EmitterParam.resolveCurve`). **/
	function locateRel( path : String ) : Null<RawNode> {
		var p = root;
		var dashed = ~/^(.*)-([0-9]+)$/;
		for( part in path.split(".") ) {
			var found = null;
			for( c in p.children )
				if( c.name == part ) {
					found = c;
					break;
				}
			if( found == null && dashed.match(part) ) {
				var name = dashed.matched(1), n = Std.parseInt(dashed.matched(2));
				for( c in p.children )
					if( c.name == name && n-- == 0 ) {
						found = c;
						break;
					}
			}
			if( found == null ) return null;
			p = found;
		}
		return p;
	}

	/**
		A curve next to `src` in an emitter: a reference to it (scaled by `refScale`) by its path from the
		root of the file when it can be written, else a copy of it scaled by `copyScale`.
	**/
	function linearCopyRel( src : RawNode, name : String, refScale : Float, copyScale : Float, owner : Prefab ) : RawNode {
		var rel = [];
		var p = src;
		var ok = true;
		while( p != root ) {
			if( p.name == "" || p.name.indexOf("-") >= 0 || p.name.indexOf(".") >= 0 ) ok = false;
			rel.unshift(p.uniqueName());
			p = p.parent;
		}
		// the path of the emitter from the root, as `locatePrefab` reads it
		var o : Prefab = owner;
		while( o != null && o.parent != null ) {
			if( o.name == null || o.name == "" || o.name.indexOf("-") >= 0 || o.name.indexOf(".") >= 0 ) ok = false;
			o = o.parent;
		}
		if( ok && pathPrefix != null && pathPrefix != "" ) {
			var d = newCurve(freeName(root, name));
			d.blendMode = 3;
			d.blendParam = pathPrefix + "." + rel.join(".");
			if( refScale != 1 ) d.scale = refScale;
			// root.data.children is the array of the raw children of the emitter
			return addChild(root, d);
		}
		var d : Dynamic = deepCopy(src.data);
		d.name = freeName(root, name);
		var n = addChild(root, d);
		indexUsers(n);
		bakeLinear(n, copyScale, 0, false);
		return n;
	}
}
