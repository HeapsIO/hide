package hrt.prefab.fx;

import hrt.prefab.fx.Value;

enum ParamKind {
	Spawn;
	Particle;
}

enum ParamMode {
	Constant( value : Float );
	Range( min : Float, max : Float );
	Curve( curve : String );
	RandomCurve( curve : String, spreadMin : Float, spreadMax : Float );
	CurveRange( curve : String );
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
	var ?desc : String;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z"];

	public static function animKey( def : ModeParamDef, comp : Int, ?field : String ) {
		var k = def.def.length == 1 ? def.name : def.name + ":" + COMPONENTS[comp];
		return field == null ? k : k + ":" + field;
	}

	/** The animation curve names of the property `prop` of `prefab` (the min and max of a Range), null if it is not an emitter or not animatable **/
	public static function animKeys( prefab : Prefab, prop : String ) : Array<String> {
		if( !EmitterHelper.isEmitter(prefab) )
			return null;
		var parts = prop.split(":");
		var def = Lambda.find(EmitterHelper.getModeParams(prefab), p -> p.name == parts[0]);
		if( def == null )
			return Lambda.exists(EmitterHelper.getParams(prefab), p -> p.animate == true && p.name == prop) ? [prop] : null;
		var i = parts.length > 1 ? COMPONENTS.indexOf(parts[1]) : 0;
		if( def.kind == Particle || i < 0 )
			return null;
		return switch( EmitterHelper.getMode(prefab, def.name, i) ) {
		case Range(_): [animKey(def, i, "min"), animKey(def, i, "max")];
		case null, _: [animKey(def, i)];
		}
	}

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

	public static function getParamSize( v : hxsl.Ast.TVar ) : Int {
		return switch( v.type ) {
		case TVec(n, VFloat) if( v.name.toLowerCase().indexOf("color") < 0 ): n;
		case TFloat, TInt, TBool: 1;
		default: 0;
		}
	}

	public static function baseComponent( prop : Dynamic, size : Int, i : Int ) : Float {
		var c : Dynamic = size == 1 ? prop : Std.isOfType(prop, Array) ? prop[i] : null;
		return Std.isOfType(c, Float) || Std.isOfType(c, Int) ? c : 0.0;
	}

	public static function parseMode( v : Dynamic ) : ParamMode {
		if( v == null )
			return null;
		if( Std.isOfType(v, Float) || Std.isOfType(v, Int) )
			return Constant(v);
		inline function num( v : Dynamic, def : Float ) : Float return v ?? def;
		return switch( (v.mode : String) ) {
		case "Range": Range(num(v.min, 0), num(v.max, 0));
		case "Curve": Curve(v.curve);
		case "RandomCurve": RandomCurve(v.curve, num(v.spreadMin, 0), num(v.spreadMax, 0));
		case "CurveRange": CurveRange(v.curve);
		default: null;
		}
	}

	public static function saveMode( m : ParamMode ) : Dynamic {
		return switch( m ) {
		case null: null;
		case Constant(v): v;
		case Range(min, max): { mode: "Range", min: min, max: max };
		case Curve(s): { mode: "Curve", curve: s };
		case RandomCurve(s, spreadMin, spreadMax):
			var o : Dynamic = { mode: "RandomCurve", curve: s };
			if( spreadMin != 0 ) o.spreadMin = spreadMin;
			if( spreadMax != 0 ) o.spreadMax = spreadMax;
			o;
		case CurveRange(s): { mode: "CurveRange", curve: s };
		}
	}

	/**
		The random spread of a RandomCurve as an affine function of the value `v` of its curve, `spread + slope * v`: `spreadMin` at the
		lowest value of the curve, `spreadMax` at the highest, `spreadMin` for a flat curve.
	**/
	public static function spreadLine( range : { min : Float, max : Float }, spreadMin : Float, spreadMax : Float ) : { spread : Float, slope : Float } {
		var d = range.max - range.min;
		if( d <= 1e-9 * Math.max(1, Math.abs(range.max)) )
			return { spread: spreadMin, slope: 0 };
		var slope = (spreadMax - spreadMin) / d;
		return { spread: spreadMin - slope * range.min, slope: slope };
	}

	/** The range of the values of a param curve: both of its curves for a blend **/
	public static function paramCurveRange( pc : ParamCurve ) : { min : Float, max : Float } {
		var r = pc.c1.getValueRange();
		if( pc.c2 != null ) {
			var r2 = pc.c2.getValueRange();
			r = { min: Math.min(r.min, r2.min), max: Math.max(r.max, r2.max) };
		}
		return r;
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
	public var randomSlots(default, null) = 0;

	public function new( owner : Prefab ) {
		this.owner = owner;
	}

	public static function particleCurve( owner : Prefab, c : ParticleCurve, def : Float ) : Value {
		return curve(owner, c.curve, def);
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
		case RandomCurve(s, spreadMin, spreadMax):
			var rid = randomSlots++;
			switch( curve(owner, s, def) ) {
			case VCurve(c):
				var l = EmitterParam.spreadLine(c.getValueRange(), spreadMin, spreadMax);
				VRandomCurve(rid, c, l.spread, l.slope);
			case VParamCurve(pc):
				var l = EmitterParam.spreadLine(EmitterParam.paramCurveRange(pc), spreadMin, spreadMax);
				VRandomParamCurve(rid, pc, l.spread, l.slope);
			case v:
				// a flat curve: the spread at its lowest value
				var k = switch( v ) { case VConst(k): k; default: 0.; };
				VRandom(rid, k - spreadMin, k + spreadMin);
			}
		case CurveRange(s):
			var c = EmitterParam.resolveCurve(owner, s);
			if( c == null )
				Evaluator.vVal(def);
			else if( c.blendMode != hrt.prefab.fx.Curve.CurveBlendMode.Range )
				throw owner.getAbsPath(true) + ': a Curve Range needs a curve in Range mode';
			else
				VCurveRange(randomSlots++, c.datas[0], c.datas[1]);
		case null, _: fixedValue(owner, m, def);
		}
	}

	public function animated( name : String, base : Value ) : Value {
		return hrt.prefab.fx.Curve.getCurve(owner, name)?.makeVal() ?? base;
	}

	function mode( def : ModeParamDef, i : Int ) : ParamMode {
		return EmitterHelper.getMode(owner, def.name, i);
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
					return hrt.prefab.fx.Curve.getCurve(owner, EmitterParam.animKey(def, i, field))?.makeVal() ?? VConst(v);
				}
				{ rid: randomSlots++, min: bound("min", min), max: bound("max", max) };
			case null, _:
				var v = animated(EmitterParam.animKey(def, i), fixedValue(owner, m, def.def[i]));
				{ rid: -1, min: v, max: v };
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
