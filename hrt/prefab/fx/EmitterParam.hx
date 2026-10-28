package hrt.prefab.fx;

import hrt.prefab.fx.Value;

enum ParamKind {
	Spawn;
	Particle;
	Multiplier;
}

enum ParamMode {
	Constant( value : Float );
	Range( min : Float, max : Float );
	Curve( curve : String );
	RandomCurve( curve : String, fromMin : Float, fromMax : Float, toMin : Float, toMax : Float );
	CurveRange( a : String, b : String );
}

typedef ParamVec2 = { ?x : ParamMode, ?y : ParamMode };
typedef ParamVec3 = { > ParamVec2, ?z : ParamMode };

typedef ParticleCurve = { curve : String };

typedef ParticleShaderParam = { name : String, comps : Array<ParticleCurve> };

typedef ModeParamDef = {
	var name : String;
	var t : hrt.prefab.Props.PropType;
	var def : Array<Float>;
	var kind : ParamKind;
	var groupName : String;
	var ?disp : String;
}

interface ParamModes {
	function getMode( name : String, comp : Int ) : ParamMode;
	function setMode( name : String, comp : Int, m : ParamMode ) : Void;
}

interface ParamOwner extends ParamModes {
	function getSettings() : Array<EmitterHelper.ParamDef>;
	function getModeParams() : Array<ModeParamDef>;
	function onSettingChange( ctx : hrt.prefab.EditContext2, name : String ) : Void;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	public static function animKey( def : ModeParamDef, comp : Int, ?field : String ) {
		var k = def.def.length == 1 ? def.name : def.name + ":" + COMPONENTS[comp];
		return field == null ? k : k + ":" + field;
	}

	// A constant is a plain number, the other modes an object with a `mode` field, a vector an object of its components

	public static function parseVec( v : Dynamic ) : ParamVec3 {
		if( v == null )
			return null;
		var out : ParamVec3 = { x: parseMode(v.x), y: parseMode(v.y), z: parseMode(v.z) };
		return out.x == null && out.y == null && out.z == null ? null : out;
	}

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

	public static function withComp( v : Dynamic, i : Int, m : ParamMode ) : ParamVec3 {
		var out : ParamVec3 = { x: i == 0 ? m : comp(v, 0), y: i == 1 ? m : comp(v, 1), z: i == 2 ? m : comp(v, 2) };
		return out.x == null && out.y == null && out.z == null ? null : out;
	}

	public static function particleDim( v : hxsl.Ast.TVar ) : Int {
		return switch( v.type ) {
		case TVec(n, VFloat) if( v.name.toLowerCase().indexOf("color") < 0 ): n;
		case TFloat, TInt, TBool: 1;
		default: 0;
		}
	}

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
		var from : Dynamic = v.from, to : Dynamic = v.to;
		return switch( (v.mode : String) ) {
		case "Range": Range(num(v.min, 0), num(v.max, 0));
		case "Curve": Curve(v.curve);
		case "RandomCurve": RandomCurve(v.curve, num(from?.min, 0), num(from?.max, 0), num(to?.min, 1), num(to?.max, 1));
		case "CurveRange": CurveRange(v.a, v.b);
		default: null;
		}
	}

	public static function saveMode( m : ParamMode ) : Dynamic {
		return switch( m ) {
		case null: null;
		case Constant(v): v;
		case Range(min, max): { mode: "Range", min: min, max: max };
		case Curve(s): { mode: "Curve", curve: s };
		case RandomCurve(s, f0, f1, t0, t1):
			var o : Dynamic = { mode: "RandomCurve", curve: s };
			if( f0 != 0 || f1 != 0 ) o.from = { min: f0, max: f1 };
			if( t0 != 1 || t1 != 1 ) o.to = { min: t0, max: t1 };
			o;
		case CurveRange(a, b): { mode: "CurveRange", a: a, b: b };
		}
	}

	/** Null when the curve or a prefab on its path is disabled **/
	public static function resolveCurve( owner : Prefab, path : String ) : Curve {
		var curve = owner.locatePrefab(path)?.to(hrt.prefab.fx.Curve);
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

/** The values `makeValues` gives an emitter object, never modified: out of the editor, the clones of an emitter share the ones of their source **/
class EmitterValues {
	public var def : hrt.prefab.fx.Emitter.InstanceDef;
	public var settings : Array<Value> = [];
	public var spawn : Array<Array<SpawnValue>> = [];
	public var randomSlots : Int = 0;
	public function new( def ) {
		this.def = def;
	}
}

class ParamBuilder {

	var owner : Prefab;
	var modes : ParamOwner;
	public var randomSlots(default, null) = 0;

	public function new( owner : Prefab, ?modes : ParamOwner ) {
		this.owner = owner;
		this.modes = modes;
	}

	public static function particleCurve( owner : Prefab, c : ParticleCurve, def : Float ) : Value {
		return curve(owner, c.curve, def);
	}

	/** 1 for a missing curve **/
	public static function curveValue( owner : Prefab, path : String ) : Value {
		return EmitterParam.resolveCurve(owner, path)?.makeVal() ?? VConst(1.0);
	}

	static inline function at( from : Float, to : Float, k : Float ) {
		return k == 0 ? from : k == 1 ? to : from + (to - from) * k;
	}

	/** `def` for a missing curve **/
	static function curve( owner : Prefab, s : String, def : Float ) : Value {
		return EmitterParam.resolveCurve(owner, s)?.makeVal() ?? Evaluator.vVal(def);
	}

	public static function fixedValue( owner : Prefab, m : ParamMode, def : Float ) : Value {
		return switch( m ) {
		case null: Evaluator.vVal(def);
		case Constant(v): Evaluator.vVal(v);
		case Curve(s): curve(owner, s, def);
		default: throw "Random mode " + m + " not supported here";
		}
	}

	public function comp( m : ParamMode, def : Float ) : Value {
		return switch( m ) {
		case Range(min, max): VRandom(randomSlots++, min, max);
		case RandomCurve(s, f0, f1, t0, t1):
			var rid = randomSlots++;
			switch( curveValue(owner, s) ) {
			case VCurve(c): VRandomCurve(rid, { c1: c, c2: null, param: null }, f0, f1, t0, t1);
			case VParamCurve(pc): VRandomCurve(rid, pc, f0, f1, t0, t1);
			case VConst(k): VRandom(rid, at(f0, t0, k), at(f1, t1, k));
			default: VRandom(rid, t0, t1);
			}
		case CurveRange(a, b):
			var va = curve(owner, a, def), vb = curve(owner, b, def);
			switch( [va, vb] ) {
			case [VCurve(ca), VCurve(cb)]: VCurveRange(randomSlots++, ca, cb);
			default: throw owner.getAbsPath(true) + ': a Curve Range needs two plain curves, not $va and $vb';
			}
		case null, _: fixedValue(owner, m, def);
		}
	}

	public function animated( name : String, base : Value ) : Value {
		var c = hrt.prefab.fx.Curve.getCurve(owner, name);
		if( c == null )
			return base;
		if( c.blendMode != RandomBlend )
			return c.makeVal();
		var a = Std.downcast(c.children[0], hrt.prefab.fx.Curve), b = Std.downcast(c.children[1], hrt.prefab.fx.Curve);
		if( a == null || b == null || !a.isPlain() || !b.isPlain() )
			throw c.getAbsPath(true) + ": a random blend needs two plain curves";
		return VCurveRange(randomSlots++, a.data, b.data);
	}

	function mode( def : ModeParamDef, i : Int ) : ParamMode {
		return modes.getMode(def.name, i);
	}

	function component( def : ModeParamDef, i : Int ) : Value {
		var m = mode(def, i);
		return def.kind == Particle ? comp(m, def.def[i]) : animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i]));
	}

	public function spawn( def : ModeParamDef ) : Array<SpawnValue> {
		return [for( i in 0...def.def.length ) {
			var m = mode(def, i);
			var s : SpawnValue = switch( m ) {
			case Range(min, max):
				function bound( field : String, v : Float ) {
					var c = hrt.prefab.fx.Curve.getCurve(owner, EmitterParam.animKey(def, i, field));
					if( c != null && c.blendMode == RandomBlend )
						throw c.getAbsPath(true) + ": a random blend on a range bound is not supported";
					return c?.makeVal() ?? VConst(v);
				}
				{ rid: randomSlots++, min: bound("min", min), max: bound("max", max) };
			case null, _:
				switch( animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i])) ) {
				case VCurveRange(rid, a, b): { rid: rid, min: VCurve(a), max: VCurve(b) };
				case v: { rid: -1, min: v, max: v };
				}
			}
			s;
		}];
	}

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
