package hrt.prefab.fx;

import hrt.prefab.Curve;
import hrt.prefab.fx.Value;

enum ParamKind {
	/** Constant or Range, read when the particle spawns **/
	Spawn;
	/** Every mode, over the particle life **/
	Particle;
	/** Constant, read every frame **/
	Multiplier;
}

enum ParamShape {
	SCurve(path : String);
	SEasing(e : Easing);
}

/** The mode of a param component, see emitter-spec.md **/
enum ParamMode {
	MConstant( value : Float );
	MRange( min : Float, max : Float );
	MCurve( shape : ParamShape, from : Float, to : Float );
	MRandomCurve( shape : ParamShape, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
	MCurveRange( a : ParamShape, aFrom : Float, aTo : Float, b : ParamShape, bFrom : Float, bTo : Float );
}

/** One mode per component, null when unset **/
typedef ParamValue = Array<Null<ParamMode>>;

/** Path of the animation curve of each animated value, by `EmitterParam.animKey` **/
typedef AnimCurves = Map<String, String>;

typedef ModeParamDef = {
	var name : String;
	var t : hrt.prefab.Props.PropType;
	var def : Array<Float>;
	var kind : ParamKind;
	var groupName : String;
	var ?disp : String;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	/** `startSpeed.x.min`: the param, its component for a vector, the bound of a range **/
	public static function animKey( def : ModeParamDef, comp : Int, ?field : String ) {
		var k = def.def.length == 1 ? def.name : def.name + "." + COMPONENTS[comp];
		return field == null ? k : k + "." + field;
	}

	public static function span( m : Null<ParamMode>, def : Float ) : { min : Float, max : Float } {
		return switch( m ) {
		case MRange(min, max): { min: min, max: max };
		case MConstant(v): { min: v, max: v };
		default: { min: def, max: def };
		}
	}

	// A constant is a plain number, the other modes an object with a `mode` field

	public static function parse( v : Dynamic, dim : Int ) : Null<ParamValue> {
		if( v == null )
			return null;
		var a : Array<Dynamic> = Std.isOfType(v, Array) ? v : [v];
		var out = [], any = false;
		for( i in 0...dim ) {
			var m = parseMode(a[i]);
			out.push(m);
			if( m != null ) any = true;
		}
		return any ? out : null;
	}

	public static function save( v : Null<ParamValue> ) : Dynamic {
		if( v == null || !Lambda.exists(v, m -> m != null) )
			return null;
		return v.length == 1 ? saveMode(v[0]) : [for( m in v ) saveMode(m)];
	}

	static function parseMode( v : Dynamic ) : Null<ParamMode> {
		if( v == null )
			return null;
		if( Std.isOfType(v, Float) || Std.isOfType(v, Int) )
			return MConstant(v);
		inline function num( v : Dynamic, def : Float ) : Float return v ?? def;
		function shape( o : Dynamic ) : ParamShape {
			var ease : String = o.ease;
			return o.curve != null ? SCurve(o.curve) : SEasing(ease != null && Easing.isValid(ease) ? ease : Linear);
		}
		var from : Dynamic = v.from, to : Dynamic = v.to, a : Dynamic = v.a, b : Dynamic = v.b;
		return switch( (v.mode : String) ) {
		case "Range": MRange(num(v.min, 0), num(v.max, 0));
		case "Curve": MCurve(shape(v), num(from, 0), num(to, 1));
		case "RandomCurve": MRandomCurve(shape(v), num(from?.min, 0), num(from?.max, 0), num(to?.min, 1), num(to?.max, 1));
		case "CurveRange": MCurveRange(shape(a), num(a.from, 0), num(a.to, 1), shape(b), num(b.from, 0), num(b.to, 1));
		default: null;
		}
	}

	static function saveMode( m : Null<ParamMode> ) : Dynamic {
		function curve( s : ParamShape, from : Float, to : Float ) : Dynamic {
			var o : Dynamic = switch( s ) { case SCurve(path): { curve: path }; case SEasing(e): { ease: (e : String) }; };
			if( from != 0 ) o.from = from;
			if( to != 1 ) o.to = to;
			return o;
		}
		return switch( m ) {
		case null: null;
		case MConstant(v): v;
		case MRange(min, max): { mode: "Range", min: min, max: max };
		case MCurve(s, from, to):
			var o = curve(s, from, to);
			o.mode = "Curve";
			o;
		case MRandomCurve(s, f0, f1, t0, t1):
			var o = curve(s, 0, 1);
			o.mode = "RandomCurve";
			if( f0 != 0 || f1 != 0 ) o.from = { min: f0, max: f1 };
			if( t0 != 1 || t1 != 1 ) o.to = { min: t0, max: t1 };
			o;
		case MCurveRange(a, af, at, b, bf, bt): { mode: "CurveRange", a: curve(a, af, at), b: curve(b, bf, bt) };
		}
	}

	/** `[{ param: key, curve: path }, ...]` **/
	public static function parseAnimCurves( v : Array<Dynamic> ) : AnimCurves {
		return [for( b in v ) (b.param : String) => (b.curve : String)];
	}

	public static function saveAnimCurves( m : Null<AnimCurves> ) : Dynamic {
		if( m == null )
			return null;
		var keys = [for( k in m.keys() ) k];
		keys.sort(Reflect.compare);
		return keys.length == 0 ? null : [for( k in keys ) { param: k, curve: m.get(k) }];
	}

	/** The curve at `path` under `owner`: names separated by dots, `name-N` for the Nth sibling of that name **/
	public static function resolveCurve( owner : Prefab, path : String ) : Null<Curve> {
		var p = owner;
		for( part in path.split(".") ) {
			var found = Lambda.find(p.children, c -> c.name == part);
			var dash = part.lastIndexOf("-");
			if( found == null && dash > 0 ) {
				var name = part.substr(0, dash), n = Std.parseInt(part.substr(dash + 1));
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
	Builds the values of the params of an emitter. Each random component takes the next random
	slot, a random per particle drawn by the emitter.
**/
class ParamBuilder {

	var owner : Prefab;
	var anim : AnimCurves;
	public var randomSlots(default, null) = 0;

	public function new( owner : Prefab, anim : AnimCurves ) {
		this.owner = owner;
		this.anim = anim;
	}

	public static function shape( owner : Prefab, s : ParamShape ) : Value {
		return switch( s ) {
		case SCurve(path):
			// a missing curve leaves the value at `to`
			EmitterParam.resolveCurve(owner, path)?.makeVal() ?? VConst(1.0);
		case SEasing(e): VEasing(e);
		}
	}

	static inline function curve( owner : Prefab, s : ParamShape, from : Float, to : Float ) : Value {
		return VLerp(VConst(from), VConst(to), shape(owner, s));
	}

	/** The value of a component without randomness: unset, Constant or Curve **/
	public static function fixedValue( owner : Prefab, m : Null<ParamMode>, def : Float ) : Value {
		return switch( m ) {
		case null: Evaluator.vVal(def);
		case MConstant(v): Evaluator.vVal(v);
		case MCurve(s, from, to): curve(owner, s, from, to);
		default: throw "Random mode " + m + " not supported here";
		}
	}

	static inline function range( rid : Int, min : Float, max : Float ) : Value {
		return VRandom(rid, (max - min) * 0.5, (max + min) * 0.5);
	}

	public function comp( m : Null<ParamMode>, def : Float ) : Value {
		return switch( m ) {
		case MRange(min, max): range(randomSlots++, min, max);
		case MRandomCurve(s, f0, f1, t0, t1):
			var rid = randomSlots++;
			VLerp(range(rid, f0, f1), range(rid, t0, t1), shape(owner, s));
		case MCurveRange(a, af, at, b, bf, bt):
			VLerp(curve(owner, a, af, at), curve(owner, b, bf, bt), VRandom(randomSlots++, 0.5, 0.5));
		default: fixedValue(owner, m, def);
		}
	}

	/** The value of animation curve `key`, `base` when there is none **/
	public function animated( key : String, base : Value ) : Value {
		var path = anim?.get(key);
		var c = path == null ? null : EmitterParam.resolveCurve(owner, path);
		if( c == null )
			return base;
		if( c.blendMode == RandomBlend )
			return VLerp(VCurve(Std.downcast(c.children[0], Curve)), VCurve(Std.downcast(c.children[1], Curve)), VRandom(randomSlots++, 0.5, 0.5));
		return c.makeVal();
	}

	/** The bounds of component `i` of a spawn param, the same value for a Constant **/
	public function bounds( def : ModeParamDef, value : Null<ParamValue>, i : Int ) : { min : Value, max : Value } {
		var m = value == null ? null : value[i];
		switch( m ) {
		case MRange(min, max):
			return { min: animated(EmitterParam.animKey(def, i, "min"), VConst(min)), max: animated(EmitterParam.animKey(def, i, "max"), VConst(max)) };
		default:
			var v = animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i]));
			return { min: v, max: v };
		}
	}

	function component( def : ModeParamDef, value : Null<ParamValue>, i : Int ) : Value {
		var m = value == null ? null : value[i];
		return switch( [def.kind, m] ) {
		case [Particle, _]: comp(m, def.def[i]);
		case [Spawn, MRange(_)]:
			var b = bounds(def, value, i);
			switch( [b.min, b.max] ) {
			case [VConst(min), VConst(max)]: range(randomSlots++, min, max);
			default: VLerp(b.min, b.max, VRandom(randomSlots++, 0.5, 0.5));
			}
		default: animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i]));
		}
	}

	/** A vector is a `VVector` of 3 components, `VZero` when they are all 0, `VConst(1)` when they are all 1 **/
	public function param( def : ModeParamDef, value : Null<ParamValue> ) : Value {
		if( def.def.length == 1 )
			return component(def, value, 0);
		var v = VVector(component(def, value, 0), component(def, value, 1), def.def.length > 2 ? component(def, value, 2) : VZero);
		return switch( v ) {
		case VVector(VZero, VZero, VZero): VZero;
		case VVector(VConst(1.0), VConst(1.0), VConst(1.0)): VConst(1.0);
		default: v;
		}
	}
}
