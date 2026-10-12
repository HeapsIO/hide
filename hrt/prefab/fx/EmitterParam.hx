package hrt.prefab.fx;

import hrt.prefab.Curve;
import hrt.prefab.fx.Value;
import hrt.prefab.fx.Evaluator;

/**
	Which modes a param can take, and over which time it is read.
	The emitter settings (rate, angle, shape dimensions...) are plain values, not part of this.
**/
enum ParamGroup {
	/** Constant or Range, read when the particle spawns. The value takes an animation curve over the FX time. **/
	Spawn;
	/** All the modes, over the particle life. **/
	Particle;
	/** Constant, read every frame. The value takes an animation curve over the FX time. **/
	Multiplier;
}

/** What a curve mode follows over the particle life, from 0 (`from`) to 1 (`to`). **/
enum ParamShape {
	/** A curve prefab, by path from the prefab that owns the param (see `EmitterParam.resolveCurve`). Its blend, remap and loop options apply. **/
	SCurve(path : String);
	SEasing(e : Easing);
}

/**
	The mode of one component of a param, with its fields. A null mode is an unset
	component, which takes the default value of the param.

	`u` is a random in [0, 1], one per particle and component, shared by all the random
	fields of the mode. `s(t)` is the shape at the particle life `t`.
**/
enum ParamMode {
	/** `value` **/
	MConstant( value : Float );
	/** `lerp(min, max, u)` **/
	MRange( min : Float, max : Float );
	/** `lerp(from, to, s(t))` **/
	MCurve( shape : ParamShape, from : Float, to : Float );
	/** `lerp(lerp(fromMin, fromMax, u), lerp(toMin, toMax, u), s(t))` **/
	MRandomCurve( shape : ParamShape, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
	/** `lerp(lerp(aFrom, aTo, a(t)), lerp(bFrom, bTo, b(t)), u)` **/
	MCurveRange( a : ParamShape, aFrom : Float, aTo : Float, b : ParamShape, bFrom : Float, bTo : Float );
}

/** The name of a mode, as serialized **/
enum abstract ParamModeKind(String) from String to String {
	var KConstant = "Constant";
	var KRange = "Range";
	var KCurve = "Curve";
	var KRandomCurve = "RandomCurve";
	var KCurveRange = "CurveRange";
}

/**
	The animation curves (over the FX time) of the params of an emitter, by key (see `EmitterParam.animKey`):
	the path of the curve from the emitter, like `SCurve`. An animation curve holds the value of what it
	animates: an emitter setting (`emitRate`...), the `value`, `min` or `max` of a spawn param
	component, a multiplier. Curve names carry no meaning.
**/
typedef AnimCurves = Map<String, String>;

/** One mode per component (a scalar param has one), null when unset. A null `ParamValue` is a param with every component unset. **/
typedef ParamValue = Array<Null<ParamMode>>;

typedef ModeParamDef = {
	var name : String;
	var disp : String;
	var group : ParamGroup;
	/** Default value of each component, a scalar param has one **/
	var def : Array<Float>;
	/** Slider range in the inspector **/
	var min : Float;
	var max : Float;
	/** Inspector category **/
	var category : String;
	/**
		Spawn and multiplier params: their `value` (a constant or unset component), or `min` / `max`
		(a range), take an animation curve over the FX time, see `AnimCurves`.
	**/
	var ?animated : Bool;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	/**
		The key of an animation curve in `AnimCurves`: the param name, `.x/.y/.z` for a component of a
		vector, `.min` / `.max` for the bounds of a range (`startSpeed.x.min`). `comp` is -1 for a scalar.
	**/
	public static function animKey( name : String, comp : Int, ?field : String ) {
		var k = comp < 0 ? name : name + "." + COMPONENTS[comp];
		return field == null ? k : k + "." + field;
	}

	/** The key of the animation curve of component `i` of `def` (see `animKey`). **/
	public static function paramAnimKey( def : ModeParamDef, i : Int, ?field : String ) {
		return animKey(def.name, def.def.length == 1 ? -1 : i, field);
	}

	public static function parseAnimCurves( v : Dynamic ) : AnimCurves {
		var out : AnimCurves = [];
		if( v != null )
			for( k in Reflect.fields(v) ) {
				var p : Dynamic = Reflect.field(v, k);
				if( p != null )
					out.set(k, Std.string(p));
			}
		return out;
	}

	public static function saveAnimCurves( m : AnimCurves ) : Dynamic {
		if( m == null || !m.iterator().hasNext() )
			return null;
		var keys = [for( k in m.keys() ) k];
		keys.sort(Reflect.compare);
		var o = {};
		for( k in keys )
			Reflect.setField(o, k, m.get(k));
		return o;
	}

	public static function kind( m : ParamMode ) : ParamModeKind {
		return switch( m ) {
		case MConstant(_): KConstant;
		case MRange(_): KRange;
		case MCurve(_): KCurve;
		case MRandomCurve(_): KRandomCurve;
		case MCurveRange(_): KCurveRange;
		}
	}

	public static function modes( g : ParamGroup ) : Array<ParamModeKind> {
		return switch( g ) {
		case Spawn: [KConstant, KRange];
		case Particle: [KConstant, KRange, KCurve, KRandomCurve, KCurveRange];
		case Multiplier: [KConstant];
		}
	}

	/** Whether the mode draws a random per particle. **/
	public static function isRandom( m : Null<ParamMode> ) {
		return switch( m ) {
		case null, MConstant(_), MCurve(_): false;
		default: true;
		}
	}

	/**
		The mode `kind` closest to `m` (an unset `m` is the constant `def`): the values at
		the start / end of the curve and the low / high bounds of the ranges are kept, and
		a missing shape is `Linear`.
	**/
	public static function convert( m : Null<ParamMode>, kind : ParamModeKind, def : Float ) : ParamMode {
		var fromLo = def, fromHi = def, toLo = def, toHi = def;
		var sa : ParamShape = null, sb : ParamShape = null;
		switch( m ) {
		case null:
		case MConstant(v): fromLo = fromHi = toLo = toHi = v;
		case MRange(lo, hi): fromLo = toLo = lo; fromHi = toHi = hi;
		case MCurve(s, f, t): sa = sb = s; fromLo = fromHi = f; toLo = toHi = t;
		case MRandomCurve(s, f0, f1, t0, t1): sa = sb = s; fromLo = f0; fromHi = f1; toLo = t0; toHi = t1;
		case MCurveRange(a, af, at, b, bf, bt): sa = a; sb = b; fromLo = af; toLo = at; fromHi = bf; toHi = bt;
		}
		sa = sa ?? SEasing(Linear);
		sb = sb ?? sa;
		return switch( kind ) {
		case KConstant: MConstant(toLo);
		case KRange: MRange(toLo, toHi);
		case KCurve: MCurve(sa, fromLo, toLo);
		case KRandomCurve: MRandomCurve(sa, fromLo, fromHi, toLo, toHi);
		case KCurveRange: MCurveRange(sa, fromLo, toLo, sb, fromHi, toHi);
		default: MConstant(toLo);
		}
	}

	/** The bounds of a spawn mode (constant or range), an unset one is `def`. **/
	public static function span( m : Null<ParamMode>, def : Float ) : { min : Float, max : Float } {
		return switch( m ) {
		case null: { min: def, max: def };
		case MConstant(v): { min: v, max: v };
		case MRange(min, max): { min: min, max: max };
		default: span(convert(m, KRange, def), def);
		}
	}

	// Serialization : a constant is a plain number, the other modes an object with a `mode` field.

	public static function parse( v : Dynamic, dim : Int ) : Null<ParamValue> {
		if( v == null )
			return null;
		var out : ParamValue = [];
		if( dim == 1 && !Std.isOfType(v, Array) )
			out.push(parseMode(v));
		else {
			var a : Array<Dynamic> = Std.isOfType(v, Array) ? v : [v];
			for( i in 0...dim )
				out.push(parseMode(a[i]));
		}
		return isUnset(out) ? null : out;
	}

	public static function save( v : Null<ParamValue> ) : Dynamic {
		if( v == null || isUnset(v) )
			return null;
		if( v.length == 1 )
			return saveMode(v[0]);
		return [for( m in v ) saveMode(m)];
	}

	public static function isUnset( v : Null<ParamValue> ) {
		if( v != null )
			for( m in v )
				if( m != null )
					return false;
		return true;
	}

	public static function parseMode( v : Dynamic ) : Null<ParamMode> {
		if( v == null )
			return null;
		if( Std.isOfType(v, Float) || Std.isOfType(v, Int) )
			return MConstant(v);
		inline function num( v : Dynamic, def : Float ) : Float return v == null ? def : v;
		inline function shape( o : Dynamic ) return parseShape(o);
		var from : Dynamic = v.from, to : Dynamic = v.to;
		return switch( (v.mode : ParamModeKind) ) {
		case KConstant: MConstant(num(v.value, 0));
		case KRange: MRange(num(v.min, 0), num(v.max, 0));
		case KCurve: MCurve(shape(v), num(from, 0), num(to, 1));
		case KRandomCurve: MRandomCurve(shape(v), num(from?.min, 0), num(from?.max, 0), num(to?.min, 1), num(to?.max, 1));
		case KCurveRange:
			var a : Dynamic = v.a ?? {}, b : Dynamic = v.b ?? {};
			MCurveRange(shape(a), num(a.from, 0), num(a.to, 1), shape(b), num(b.from, 0), num(b.to, 1));
		default: null;
		}
	}

	public static function saveMode( m : Null<ParamMode> ) : Dynamic {
		inline function setShape( o : Dynamic, s : ParamShape ) {
			switch( s ) {
			case SCurve(path): o.curve = path;
			case SEasing(e): o.ease = (e : String);
			}
		}
		inline function setSpan( o : Dynamic, from : Float, to : Float ) {
			if( from != 0 ) o.from = from;
			if( to != 1 ) o.to = to;
		}
		return switch( m ) {
		case null: null;
		case MConstant(v): v;
		case MRange(min, max): { mode: (KRange : String), min: min, max: max };
		case MCurve(s, from, to):
			var o : Dynamic = { mode: (KCurve : String) };
			setShape(o, s);
			setSpan(o, from, to);
			o;
		case MRandomCurve(s, f0, f1, t0, t1):
			var o : Dynamic = { mode: (KRandomCurve : String) };
			setShape(o, s);
			if( f0 != 0 || f1 != 0 ) o.from = { min: f0, max: f1 };
			if( t0 != 1 || t1 != 1 ) o.to = { min: t0, max: t1 };
			o;
		case MCurveRange(a, af, at, b, bf, bt):
			var oa : Dynamic = {}, ob : Dynamic = {};
			setShape(oa, a);
			setSpan(oa, af, at);
			setShape(ob, b);
			setSpan(ob, bf, bt);
			{ mode: (KCurveRange : String), a: oa, b: ob };
		}
	}

	static function parseShape( o : Dynamic ) : ParamShape {
		var curve : String = o.curve;
		if( curve != null )
			return SCurve(curve);
		var ease : String = o.ease;
		return SEasing(ease != null && Easing.isValid(ease) ? ease : Linear);
	}

	// Curve references

	/**
		The curve at `path` under `owner`: names separated by dots, a name taken by several
		siblings told apart with `name-N` like `Prefab.getUniqueName`. Null if it does not
		exist or is disabled.
	**/
	public static function resolveCurve( owner : Prefab, path : String ) : Null<Curve> {
		if( path == null )
			return null;
		var p = owner;
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
			if( found == null || !found.enabled )
				return null;
			p = found;
		}
		var curve = p.to(Curve);
		#if editor
		if( curve != null && owner.shared.editor?.isHidden(curve) )
			return null;
		#end
		return curve;
	}

	/** The path of `curve` from `owner`, for `SCurve`. Null if it is not under `owner`. **/
	public static function curvePath( owner : Prefab, curve : Curve ) : Null<String> {
		var parts = [];
		var p : Prefab = curve;
		while( p != owner ) {
			if( p == null )
				return null;
			parts.unshift(p.getUniqueName());
			p = p.parent;
		}
		return parts.join(".");
	}
}

/**
	Builds the `Value` of the params of an emitter, and allocates their random slots: one per
	random component, in build order. A slot is one random per particle, drawn by the emitter
	(see `EmitterObject.reset`).
**/
class ParamBuilder {

	var owner : Prefab;
	var skips : Array<String>;
	var anim : AnimCurves;

	/** The component keys of the random slots, in slot order. **/
	public var slots(default, null) : Array<String> = [];

	/**
		`skips` lists the components that leave one slot unused before their own, which
		keeps the slot layout of the emitters upgraded from the old format (see
		`Emitter.skippedRandomSlots`).
	**/
	public function new( owner : Prefab, ?skips : Array<String>, ?anim : AnimCurves ) {
		this.owner = owner;
		this.skips = skips;
		this.anim = anim;
	}

	/** The animation curve bound to `key` (see `AnimCurves`), null if none or if it does not resolve. **/
	public function animCurve( key : String ) : Null<Curve> {
		var path = anim?.get(key);
		return path == null ? null : EmitterParam.resolveCurve(owner, path);
	}

	function slot( key : String ) {
		slots.push(key);
		return slots.length - 1;
	}

	/** A random in [lo, hi] on slot `rid`. **/
	static inline function range( rid : Int, lo : Float, hi : Float ) : Value {
		return lo == hi ? Evaluator.vVal(lo) : VRandom(rid, (hi - lo) * 0.5, (hi + lo) * 0.5);
	}

	/** `scope`: the prefab the curve paths start from, the owner by default. **/
	public function shape( s : ParamShape, ?scope : Prefab ) : Value {
		return switch( s ) {
		case SCurve(path):
			// a missing curve leaves the value at `to`
			var c = EmitterParam.resolveCurve(scope ?? owner, path);
			c != null ? c.makeVal() : VConst(1.0);
		case SEasing(e): VEasing(e);
		}
	}

	/**
		The value of one component, `key` naming it for its random slot. `scope`: the prefab the
		curve paths start from, the owner by default.
	**/
	public function comp( key : String, m : Null<ParamMode>, def : Float, ?scope : Prefab ) : Value {
		if( skips != null && skips.indexOf(key) >= 0 )
			slot(key + "~");
		inline function v( f : Float ) return Evaluator.vVal(f);
		return switch( m ) {
		case null: v(def);
		case MConstant(c): v(c);
		case MRange(min, max): VRandom(slot(key), (max - min) * 0.5, (max + min) * 0.5);
		case MCurve(s, from, to): Evaluator.vLerp(v(from), v(to), shape(s, scope));
		case MRandomCurve(s, f0, f1, t0, t1):
			var rid = slot(key);
			Evaluator.vLerp(range(rid, f0, f1), range(rid, t0, t1), shape(s, scope));
		case MCurveRange(a, af, at, b, bf, bt):
			var rid = slot(key);
			Evaluator.vLerp(Evaluator.vLerp(v(af), v(at), shape(a, scope)), Evaluator.vLerp(v(bf), v(bt), shape(b, scope)), VRandom(rid, 0.5, 0.5));
		}
	}

	/**
		The value of an emitter setting animated over the FX time: its animation curve bound to `key`,
		`base` when there is none. A curve in RandomBlend mode is a random between its two child curves.
	**/
	public function animated( base : Value, key : String ) : Value {
		var c = animCurve(key);
		if( c == null )
			return base;
		return curveValue(c, key);
	}

	function curveValue( c : Curve, key : String ) : Value {
		if( c.blendMode == RandomBlend )
			return VRandomBetweenCurves(slot(key), Std.downcast(c.children[0], Curve), Std.downcast(c.children[1], Curve));
		return c.makeVal();
	}

	/**
		The value of component `i` of a spawn or multiplier param, `key` naming it for its random slot:
		the animation curve of its `value` (constant or unset component), or of its `min` / `max` (range).
	**/
	public function animatedComp( key : String, m : Null<ParamMode>, def : ModeParamDef, i : Int ) : Value {
		switch( m ) {
		case MRange(min, max):
			var cmin = animCurve(EmitterParam.paramAnimKey(def, i, "min")), cmax = animCurve(EmitterParam.paramAnimKey(def, i, "max"));
			if( cmin == null && cmax == null )
				return comp(key, m, def.def[i]);
			if( skips != null && skips.indexOf(key) >= 0 )
				slot(key + "~");
			var rid = slot(key);
			inline function bound( c : Curve, v : Float ) return c != null ? c.makeVal() : Evaluator.vVal(v);
			return Evaluator.vLerp(bound(cmin, min), bound(cmax, max), VRandom(rid, 0.5, 0.5));
		default:
			var c = animCurve(EmitterParam.paramAnimKey(def, i));
			if( c == null )
				return comp(key, m, def.def[i]);
			if( skips != null && skips.indexOf(key) >= 0 )
				slot(key + "~");
			return curveValue(c, key);
		}
	}

	/**
		The animated bounds of a scalar spawn param drawn by the emitter itself (the life time): null
		when it has no animation curve, the constant ones are kept.
	**/
	public function animatedSpan( def : ModeParamDef, m : Null<ParamMode> ) : Null<{ min : Value, max : Value }> {
		var span = EmitterParam.span(m, def.def[0]);
		switch( m ) {
		case MRange(_):
			var cmin = animCurve(EmitterParam.paramAnimKey(def, 0, "min")), cmax = animCurve(EmitterParam.paramAnimKey(def, 0, "max"));
			if( cmin == null && cmax == null )
				return null;
			return { min: cmin != null ? cmin.makeVal() : Evaluator.vVal(span.min), max: cmax != null ? cmax.makeVal() : Evaluator.vVal(span.max) };
		default:
			var c = animCurve(EmitterParam.paramAnimKey(def, 0));
			if( c == null )
				return null;
			var v = c.makeVal();
			return { min: v, max: v };
		}
	}

	/**
		The value of a param. A vector is a `VVector` of 3 components (the third is 0 for a 2D
		one), `VZero` when all are 0 and `VConst(1)` when all are 1.
	**/
	public function param( def : ModeParamDef, value : Null<ParamValue> ) : Value {
		var dim = def.def.length;
		inline function one( key : String, i : Int ) {
			var m = value == null ? null : value[i];
			return def.animated == true ? animatedComp(key, m, def, i) : comp(key, m, def.def[i]);
		}
		if( dim == 1 )
			return one(def.name, 0);
		var c = [for( i in 0...dim ) one(def.name + "." + EmitterParam.COMPONENTS[i], i)];
		var v : Value = VVector(c[0], c[1], c[2] ?? VZero);
		if( v.match(VVector(VZero, VZero, VZero)) )
			v = VZero;
		else if( v.match(VVector(VConst(1.0), VConst(1.0), VConst(1.0))) )
			v = VConst(1.0);
		return v;
	}
}
