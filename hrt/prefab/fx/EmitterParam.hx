package hrt.prefab.fx;

import hrt.prefab.fx.Value;

enum ParamKind {
	Spawn;
	Particle;
}

enum ParamMode {
	Constant( value : Float );
	Range( min : Float, max : Float );
	/** The curve named after the param (`EmitterParam.animKey`), like all the curves of an emitter **/
	Curve;
	RandomCurve( spreadMin : Float, spreadMax : Float );
	CurveRange;
}

typedef ParamVec2 = { ?x : ParamMode, ?y : ParamMode };
typedef ParamVec3 = { > ParamVec2, ?z : ParamMode };

typedef ParamDef = {
	var name : String;
	var t : hrt.prefab.Props.PropType;
	var def : Array<Float>;
	var kind : ParamKind;
	var groupName : String;
	var ?disp : String;
	var ?desc : String;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	/** The name of the curve of the component `comp` of a param (`name`, `name:x`), of one of its bounds with `field` (`name:x:min`) **/
	public static function animKey( def : ParamDef, comp : Int, ?field : String ) {
		return curveName(def.name, def.def.length, comp, field);
	}

	public static function curveName( name : String, size : Int, comp : Int, ?field : String ) {
		var k = size == 1 ? name : name + ":" + COMPONENTS[comp];
		return field == null ? k : k + ":" + field;
	}

	/** The animation curve names of the property `prop` of `prefab` (the min and max of a Range), null if it is not an emitter or not animatable **/
	public static function animKeys( prefab : Prefab, prop : String ) : Array<String> {
		if( !EmitterHelper.isEmitter(prefab) )
			return null;
		var parts = prop.split(":");
		var def = Lambda.find(EmitterHelper.getParams(prefab), p -> p.name == parts[0]);
		if( def == null )
			return Lambda.exists(EmitterHelper.getProperties(prefab), p -> p.animate == true && p.name == prop) ? [prop] : null;
		var i = parts.length > 1 ? COMPONENTS.indexOf(parts[1]) : 0;
		if( def.kind == Particle || i < 0 )
			return null;
		return switch( EmitterHelper.getMode(prefab, def.name, i) ) {
		case Range(_): [animKey(def, i, "min"), animKey(def, i, "max")];
		case null, _: [animKey(def, i)];
		}
	}

	public static function isCurveMode( m : ParamMode ) {
		return switch( m ) {
		case Curve, RandomCurve(_), CurveRange: true;
		case null, _: false;
		}
	}

	/** A curve named `name` under `owner`, disabled or not **/
	public static function hasCurve( owner : Prefab, name : String ) {
		return Lambda.exists(owner.children, c -> c is hrt.prefab.fx.Curve && c.name != null && c.name.toLowerCase() == name.toLowerCase());
	}

	/** The mode of the component `i` of `def` as it is saved: a curve mode without its curve (deleted) is not **/
	public static function saved( owner : Prefab, def : ParamDef, i : Int, m : ParamMode ) : ParamMode {
		return isCurveMode(m) && !hasCurve(owner, animKey(def, i)) ? null : m;
	}

	public static function savedVec( owner : Prefab, def : ParamDef, v : Dynamic ) : ParamVec3 {
		var out : ParamVec3 = { x: saved(owner, def, 0, comp(v, 0)), y: saved(owner, def, 1, comp(v, 1)), z: def.def.length > 2 ? saved(owner, def, 2, comp(v, 2)) : null };
		return out.x == null && out.y == null && out.z == null ? null : out;
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
		case "Curve": Curve;
		case "RandomCurve": RandomCurve(num(v.spreadMin, 0), num(v.spreadMax, 0));
		case "CurveRange": CurveRange;
		default: null;
		}
	}

	public static function saveMode( m : ParamMode ) : Dynamic {
		return switch( m ) {
		case null: null;
		case Constant(v): v;
		case Range(min, max): { mode: "Range", min: min, max: max };
		case Curve: { mode: "Curve" };
		case RandomCurve(spreadMin, spreadMax):
			var o : Dynamic = { mode: "RandomCurve" };
			if( spreadMin != 0 ) o.spreadMin = spreadMin;
			if( spreadMax != 0 ) o.spreadMax = spreadMax;
			o;
		case CurveRange: { mode: "CurveRange" };
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
}

/** The values `makeValues` gives an emitter object, never modified: out of the editor, the clones of an emitter share the ones of their source **/
class EmitterValues {
	public var particle : Array<Value> = [];
	public var properties : Array<Value> = [];
	public var spawn : Array<Array<SpawnValue>> = [];
	public var randomSlots : Int = 0;
	public function new() {
	}
}

class ParamBuilder {

	var owner : Prefab;
	public var randomSlots(default, null) = 0;

	public function new( owner : Prefab ) {
		this.owner = owner;
	}

	/** The curve `name` of `owner`, `def` without it **/
	public static function curve( owner : Prefab, name : String, def : Float ) : Value {
		return hrt.prefab.fx.Curve.getCurve(owner, name)?.makeVal() ?? Evaluator.vVal(def);
	}

	public static function fixedValue( owner : Prefab, m : ParamMode, name : String, def : Float ) : Value {
		return switch( m ) {
		case null: Evaluator.vVal(def);
		case Constant(v): Evaluator.vVal(v);
		case Curve: curve(owner, name, def);
		default: throw "Random mode " + m + " not supported here";
		}
	}

	/** A particle param component in mode `m`, `name` its curve **/
	public function comp( m : ParamMode, name : String, def : Float ) : Value {
		return switch( m ) {
		case Range(min, max): VRandom(randomSlots++, min, max);
		case RandomCurve(spreadMin, spreadMax):
			var rid = randomSlots++;
			switch( curve(owner, name, def) ) {
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
		case CurveRange:
			var c = hrt.prefab.fx.Curve.getCurve(owner, name);
			if( c == null )
				Evaluator.vVal(def);
			else if( c.blendMode != hrt.prefab.fx.Curve.CurveBlendMode.Range )
				throw owner.getAbsPath(true) + ': a Curve Range needs a curve in Range mode';
			else
				VCurveRange(randomSlots++, c.datas[0], c.datas[1]);
		case null, _: fixedValue(owner, m, name, def);
		}
	}

	public function animated( name : String, base : Value ) : Value {
		return hrt.prefab.fx.Curve.getCurve(owner, name)?.makeVal() ?? base;
	}

	function mode( def : ParamDef, i : Int ) : ParamMode {
		return EmitterHelper.getMode(owner, def.name, i);
	}

	function component( def : ParamDef, i : Int ) : Value {
		var m = mode(def, i), key = EmitterParam.animKey(def, i);
		return def.kind == Particle ? comp(m, key, def.def[i]) : animated(key, fixedValue(owner, m, key, def.def[i]));
	}

	public function spawn( def : ParamDef ) : Array<SpawnValue> {
		return [for( i in 0...def.def.length ) {
			var m = mode(def, i);
			var s : SpawnValue = switch( m ) {
			case Range(min, max):
				function bound( field : String, v : Float ) {
					return hrt.prefab.fx.Curve.getCurve(owner, EmitterParam.animKey(def, i, field))?.makeVal() ?? VConst(v);
				}
				{ rid: randomSlots++, min: bound("min", min), max: bound("max", max) };
			case null, _:
				var key = EmitterParam.animKey(def, i);
				var v = animated(key, fixedValue(owner, m, key, def.def[i]));
				{ rid: -1, min: v, max: v };
			}
			s;
		}];
	}

	public function param( def : ParamDef ) : Value {
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
