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

/** The mode of a param component: a value, a random in a range, or over the particle life (a curve by its path from the owner) **/
enum ParamMode {
	Constant( value : Float );
	Range( min : Float, max : Float );
	Curve( curve : String, from : Float, to : Float );
	RandomCurve( curve : String, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
	CurveRange( a : String, aFrom : Float, aTo : Float, b : String, bFrom : Float, bTo : Float );
}

/** A vector param, one mode per component, null when unset **/
typedef ParamVec2 = { ?x : ParamMode, ?y : ParamMode };
typedef ParamVec3 = { > ParamVec2, ?z : ParamMode };

/** A component of a particle shader param over the particle life: lerp(from, to, curve(t)), `curve` a path **/
typedef ParticleCurve = { curve : String, from : Float, to : Float };

/** A particle shader param, a null component keeps its prop **/
typedef ParticleShaderParam = { name : String, comps : Array<ParticleCurve> };

typedef ModeParamDef = {
	var name : String;
	var t : hrt.prefab.Props.PropType;
	var def : Array<Float>;
	var kind : ParamKind;
	var groupName : String;
	var ?disp : String;
}

/** An emitter: its settings, its params with modes and their values **/
interface ParamOwner {
	function getSettings() : Array<EmitterHelper.ParamDef>;
	function getModeParams() : Array<ModeParamDef>;
	function getMode( name : String, comp : Int ) : ParamMode;
	function setMode( name : String, comp : Int, m : ParamMode ) : Void;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	/** The name of an animation curve, `startSpeed:x:min`: the param, its component for a vector, the bound of a range **/
	public static function animKey( def : ModeParamDef, comp : Int, ?field : String ) {
		var k = def.def.length == 1 ? def.name : def.name + ":" + COMPONENTS[comp];
		return field == null ? k : k + ":" + field;
	}

	public static function span( m : ParamMode, def : Float ) : { min : Float, max : Float } {
		return switch( m ) {
		case Range(min, max): { min: min, max: max };
		case Constant(v): { min: v, max: v };
		case null, _: { min: def, max: def };
		}
	}

	// A constant is a plain number, the other modes an object with a `mode` field, a vector an object of its components

	public static function parseVec( v : Dynamic ) : ParamVec3 {
		if( v == null )
			return null;
		var out : ParamVec3 = { x: parseMode(v.x), y: parseMode(v.y), z: parseMode(v.z) };
		return out.x == null && out.y == null && out.z == null ? null : out;
	}

	// a ParamVec2 or a ParamVec3
	public static function saveVec( v : Dynamic ) : Dynamic {
		if( v == null || (v.x == null && v.y == null && v.z == null) )
			return null;
		var o : Dynamic = {};
		if( v.x != null ) o.x = saveMode(v.x);
		if( v.y != null ) o.y = saveMode(v.y);
		if( v.z != null ) o.z = saveMode(v.z);
		return o;
	}

	public static function comp( v : Dynamic, i : Int ) : ParamMode {
		return v == null ? null : i == 0 ? v.x : i == 1 ? v.y : v.z;
	}

	/** `v` with component `i` set to `m`, null when none is set **/
	public static function withComp( v : Dynamic, i : Int, m : ParamMode ) : ParamVec3 {
		var out : ParamVec3 = { x: i == 0 ? m : comp(v, 0), y: i == 1 ? m : comp(v, 1), z: i == 2 ? m : comp(v, 2) };
		return out.x == null && out.y == null && out.z == null ? null : out;
	}

	/** The components of a shader param read over the particle life: a float, or a vector that is not a color. 0 for the others. **/
	public static function particleDim( v : hxsl.Ast.TVar ) : Int {
		return switch( v.type ) {
		case TVec(n, VFloat) if( v.name.toLowerCase().indexOf("color") < 0 ): n;
		case TFloat, TInt, TBool: 1;
		default: 0;
		}
	}

	/** Component `i` of the value `prop` of a shader param of `dim` components, 0 when it is not a number **/
	public static function baseComponent( prop : Dynamic, dim : Int, i : Int ) : Float {
		var c : Dynamic = dim == 1 ? prop : Std.isOfType(prop, Array) ? prop[i] : null;
		return Std.isOfType(c, Float) || Std.isOfType(c, Int) ? c : 0.0;
	}

	public static function parseMode( v : Dynamic ) : ParamMode {
		if( v == null )
			return null;
		if( Std.isOfType(v, Float) || Std.isOfType(v, Int) )
			return Constant(v);
		inline function num( v : Dynamic, def : Float ) : Float return v ?? def;
		var from : Dynamic = v.from, to : Dynamic = v.to, a : Dynamic = v.a, b : Dynamic = v.b;
		return switch( (v.mode : String) ) {
		case "Range": Range(num(v.min, 0), num(v.max, 0));
		case "Curve": Curve(v.curve, num(from, 0), num(to, 1));
		case "RandomCurve": RandomCurve(v.curve, num(from?.min, 0), num(from?.max, 0), num(to?.min, 1), num(to?.max, 1));
		case "CurveRange": CurveRange(a.curve, num(a.from, 0), num(a.to, 1), b.curve, num(b.from, 0), num(b.to, 1));
		default: null;
		}
	}

	public static function saveMode( m : ParamMode ) : Dynamic {
		function curve( s : String, from : Float, to : Float ) : Dynamic {
			var o : Dynamic = { curve: s };
			if( from != 0 ) o.from = from;
			if( to != 1 ) o.to = to;
			return o;
		}
		return switch( m ) {
		case null: null;
		case Constant(v): v;
		case Range(min, max): { mode: "Range", min: min, max: max };
		case Curve(s, from, to):
			var o = curve(s, from, to);
			o.mode = "Curve";
			o;
		case RandomCurve(s, f0, f1, t0, t1):
			var o = curve(s, 0, 1);
			o.mode = "RandomCurve";
			if( f0 != 0 || f1 != 0 ) o.from = { min: f0, max: f1 };
			if( t0 != 1 || t1 != 1 ) o.to = { min: t0, max: t1 };
			o;
		case CurveRange(a, af, at, b, bf, bt): { mode: "CurveRange", a: curve(a, af, at), b: curve(b, bf, bt) };
		}
	}

	/** The curve at `path` under `owner` (`Prefab.locatePrefab`), null when it or a prefab on its path is disabled **/
	public static function resolveCurve( owner : Prefab, path : String ) : Curve {
		var curve = owner.locatePrefab(path)?.to(hrt.prefab.Curve);
		var p : Prefab = curve;
		while( p != null && p != owner ) {
			if( !p.enabled )
				return null;
			p = p.parent;
		}
		#if editor
		if( curve != null && owner.shared.editor?.isHidden(curve) )
			return null;
		#end
		return curve;
	}

	public static function curvePath( owner : Prefab, curve : Curve ) : String {
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
	var modes : ParamOwner;
	public var randomSlots(default, null) = 0;

	public function new( owner : Prefab, ?modes : ParamOwner ) {
		this.owner = owner;
		this.modes = modes;
	}

	public static function particleCurve( owner : Prefab, c : ParticleCurve ) : Value {
		return curve(owner, c.curve, c.from, c.to);
	}

	/** The value of the curve at `path`, from 0 to 1, 1 for a missing curve **/
	public static function curveValue( owner : Prefab, path : String ) : Value {
		return EmitterParam.resolveCurve(owner, path)?.makeVal() ?? VConst(1.0);
	}

	static inline function at( from : Float, to : Float, k : Float ) {
		return k == 0 ? from : k == 1 ? to : from + (to - from) * k;
	}

	static function curve( owner : Prefab, s : String, from : Float, to : Float ) : Value {
		return switch( curveValue(owner, s) ) {
		case VCurve(c, a, b): VCurve(c, at(from, to, a), at(from, to, b));
		case VParamCurve(c, a, b): VParamCurve(c, at(from, to, a), at(from, to, b));
		case VConst(k): VConst(at(from, to, k));
		default: VConst(to);
		}
	}

	/** The value of a component without randomness: unset, Constant or Curve **/
	public static function fixedValue( owner : Prefab, m : ParamMode, def : Float ) : Value {
		return switch( m ) {
		case null: Evaluator.vVal(def);
		case Constant(v): Evaluator.vVal(v);
		case Curve(s, from, to): curve(owner, s, from, to);
		default: throw "Random mode " + m + " not supported here";
		}
	}

	public function comp( m : ParamMode, def : Float ) : Value {
		return switch( m ) {
		case Range(min, max): VRandom(randomSlots++, min, max);
		case RandomCurve(s, f0, f1, t0, t1):
			var rid = randomSlots++;
			switch( curveValue(owner, s) ) {
			case VCurve(c, a, b), VParamCurve(c, a, b): VRandomCurve(rid, c, at(f0, t0, a), at(f1, t1, a), at(f0, t0, b), at(f1, t1, b));
			case VConst(k): VRandom(rid, at(f0, t0, k), at(f1, t1, k));
			default: VRandom(rid, t0, t1);
			}
		case CurveRange(a, aFrom, aTo, b, bFrom, bTo):
			var va = curve(owner, a, aFrom, aTo), vb = curve(owner, b, bFrom, bTo);
			switch( [va, vb] ) {
			case [VCurve(ca, a0, a1), VCurve(cb, b0, b1)]: VCurveRange(randomSlots++, ca, a0, a1, cb, b0, b1);
			default: throw owner.getAbsPath(true) + ': a Curve Range needs two plain curves, not $va and $vb';
			}
		case null, _: fixedValue(owner, m, def);
		}
	}

	/** The value of the animation curve `name`, `base` when there is none **/
	public function animated( name : String, base : Value ) : Value {
		var c = hrt.prefab.Curve.getCurve(owner, name);
		if( c == null )
			return base;
		if( c.blendMode != RandomBlend )
			return c.makeVal();
		var a = Std.downcast(c.children[0], hrt.prefab.Curve), b = Std.downcast(c.children[1], hrt.prefab.Curve);
		if( a == null || b == null || !a.isPlain() || !b.isPlain() )
			throw c.getAbsPath(true) + ": a random blend needs two plain curves";
		return VCurveRange(randomSlots++, a, 0, 1, b, 0, 1);
	}

	function mode( def : ModeParamDef, i : Int ) : ParamMode {
		return modes.getMode(def.name, i);
	}

	function component( def : ModeParamDef, i : Int ) : Value {
		var m = mode(def, i);
		return def.kind == Particle ? comp(m, def.def[i]) : animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i]));
	}

	/** A Spawn param, per component: its value, or a random between its bounds, over the FX time **/
	public function spawn( def : ModeParamDef ) : Array<SpawnValue> {
		return [for( i in 0...def.def.length ) {
			var m = mode(def, i);
			var s : SpawnValue = switch( m ) {
			case Range(min, max):
				function bound( field : String, v : Float ) {
					var c = hrt.prefab.Curve.getCurve(owner, EmitterParam.animKey(def, i, field));
					if( c != null && c.blendMode == RandomBlend )
						throw c.getAbsPath(true) + ": a random blend on a range bound is not supported";
					return c?.makeVal() ?? VConst(v);
				}
				{ rid: randomSlots++, min: bound("min", min), max: bound("max", max) };
			case null, _:
				switch( animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i])) ) {
				case VCurveRange(rid, a, a0, a1, b, b0, b1): { rid: rid, min: VCurve(a, a0, a1), max: VCurve(b, b0, b1) };
				case v: { rid: -1, min: v, max: v };
				}
			}
			s;
		}];
	}

	/** A vector is a `VVector` of 3 components, `VZero` when they are all 0, `VConst(1)` when they are all 1 **/
	public function param( def : ModeParamDef ) : Value {
		if( def.def.length == 1 )
			return component(def, 0);
		var v = VVector(component(def, 0), component(def, 1), def.def.length > 2 ? component(def, 2) : VZero);
		return switch( v ) {
		case VVector(VZero, VZero, VZero): VZero;
		case VVector(VConst(1.0), VConst(1.0), VConst(1.0)): VConst(1.0);
		default: v;
		}
	}
}
