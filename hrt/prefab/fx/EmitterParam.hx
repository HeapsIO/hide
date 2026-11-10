package hrt.prefab.fx;

import hrt.prefab.fx.Value;

enum ParamKind {
	// read at each emission step over the emitter time, random drawn by the emitter
	Emission;
	// read once per particle at spawn time, over the emitter time, random per particle
	Spawn;
	// read over the particle life, random per particle
	Particle;
}

enum ParamMode {
	Constant( value : Float );
	Range( min : Float, max : Float );
	Curve;
	RandomCurve( spreadMin : Float, spreadMax : Float );
	CurveRange;
}

// the modes of the components of a vector param, x y z
typedef ParamVec2 = Array<ParamMode>;
typedef ParamVec3 = Array<ParamMode>;

typedef ParamDef = {
	var name : String;
	var t : hrt.prefab.Props.PropType;
	var def : Array<Float>;
	var kind : ParamKind;
	var groupName : String;
	var ?disp : String;
	var ?desc : String;
}

enum EmitterField {
	// plain field read as is (can be animated by curves in emitter time)
	Property( def : EmitterHelper.PropertyDef );
	// dynamic field with modes (constant, range, curves...), random per particle or per emission cycle
	Param( def : ParamDef );
}

// see EmitterMacros
interface IEmitter {
	function getFields() : Array<EmitterField>;
	function getMode( name : String, comp : Int ) : ParamMode;
	function setMode( name : String, comp : Int, m : ParamMode ) : Void;
}

class EmitterParam {

	public static var COMPONENTS = ["x", "y", "z", "w"];

	// the curve of the component `comp` of a param in a curve mode: `name`, `name:x`
	public static function curveKey( def : ParamDef, comp : Int ) {
		return curveName(def.name, def.def.length, comp);
	}

	public static function curveName( name : String, size : Int, comp : Int ) {
		return size == 1 ? name : name + ":" + COMPONENTS[comp];
	}

	// the params have their curves in their modes
	public static function animKeys( prefab : Prefab, prop : String ) : Array<String> {
		var emitter : IEmitter = prefab is IEmitter ? cast prefab : null;
		if( emitter == null )
			return null;
		return Lambda.exists(emitter.getFields(), f -> switch( f ) { case Property(p): p.animate && p.name == prop; default: false; }) ? [prop] : null;
	}

	public static function isCurveMode( m : ParamMode ) {
		return switch( m ) {
		case Curve, RandomCurve(_), CurveRange: true;
		case null, _: false;
		}
	}

	public static function hasCurve( owner : Prefab, name : String ) {
		return Lambda.exists(owner.children, c -> c is hrt.prefab.fx.Curve && c.name != null && c.name.toLowerCase() == name.toLowerCase());
	}

	// a curve mode whose curve was deleted is not saved
	public static function saved( owner : Prefab, def : ParamDef, i : Int, m : ParamMode ) : ParamMode {
		return isCurveMode(m) && !hasCurve(owner, curveKey(def, i)) ? null : m;
	}

	// a vector param is saved as { x, y, z }, with only its set components
	public static function parseVec( v : Dynamic ) : Array<ParamMode> {
		return [for( i in 0...3 ) v == null ? null : parseMode(Reflect.field(v, COMPONENTS[i]))];
	}

	public static function saveVec( owner : Prefab, def : ParamDef, v : Array<ParamMode> ) : Dynamic {
		var o : Dynamic = null;
		for( i in 0...def.def.length ) {
			var m = saved(owner, def, i, v[i]);
			if( m == null )
				continue;
			if( o == null )
				o = {};
			Reflect.setField(o, COMPONENTS[i], saveMode(m));
		}
		return o;
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

	static function isSavedMode( v : Dynamic ) {
		return Std.isOfType(v, Float) || Std.isOfType(v, Int) || Reflect.hasField(v, "mode");
	}

	public static function loadShaderModes( v : Dynamic ) : Map<String, ParamMode> {
		if( v == null )
			return null;
		var out = new Map();
		for( name in Reflect.fields(v) ) {
			var p : Dynamic = Reflect.field(v, name);
			if( isSavedMode(p) ) {
				var m = parseMode(p);
				if( m != null ) out.set(name, m);
			} else
				for( c in COMPONENTS ) {
					var m = parseMode(Reflect.field(p, c));
					if( m != null ) out.set(name + ":" + c, m);
				}
		}
		return out;
	}

	public static function saveShaderModes( modes : Map<String, ParamMode> ) : Dynamic {
		if( modes == null )
			return null;
		var keys = [for( k in modes.keys() ) k];
		if( keys.length == 0 )
			return null;
		keys.sort(Reflect.compare);
		var out : Dynamic = {};
		for( k in keys ) {
			var parts = k.split(":");
			if( parts.length == 1 ) {
				Reflect.setField(out, k, saveMode(modes.get(k)));
				continue;
			}
			var v : Dynamic = Reflect.field(out, parts[0]);
			if( v == null )
				Reflect.setField(out, parts[0], v = {});
			Reflect.setField(v, parts[1], saveMode(modes.get(k)));
		}
		return out;
	}

	// spread + slope * v: spreadMin at the lowest value of the curve, spreadMax at the highest
	public static function spreadLine( range : { min : Float, max : Float }, spreadMin : Float, spreadMax : Float ) : { spread : Float, slope : Float } {
		var d = range.max - range.min;
		if( d <= 1e-9 * Math.max(1, Math.abs(range.max)) )
			return { spread: spreadMin, slope: 0 };
		var slope = (spreadMax - spreadMin) / d;
		return { spread: spreadMin - slope * range.min, slope: slope };
	}

	public static function paramCurveRange( pc : ParamCurve ) : { min : Float, max : Float } {
		var r = pc.c1.getValueRange();
		if( pc.c2 != null ) {
			var r2 = pc.c2.getValueRange();
			r = { min: Math.min(r.min, r2.min), max: Math.max(r.max, r2.max) };
		}
		return r;
	}
}

class ParamBuilder {

	var owner : Prefab;
	// in the order the fields are applied (`EmitterMacros`)
	public var values(default, null) : Array<Value> = [];
	public var randomSlots(default, null) = 0;
	// the random of an Emission param is drawn by the emitter: no slot
	var withSlots = true;

	public function new( owner : Prefab ) {
		this.owner = owner;
	}

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

	inline function slot() {
		return withSlots ? randomSlots++ : -1;
	}

	public function comp( m : ParamMode, name : String, def : Float ) : Value {
		return switch( m ) {
		case Range(min, max): VRandom(slot(), min, max);
		case RandomCurve(spreadMin, spreadMax):
			var rid = slot();
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
			var c = rangeCurve(owner, name);
			c == null ? Evaluator.vVal(def) : VCurveRange(slot(), c.datas[0], c.datas[1]);
		case null, _: fixedValue(owner, m, name, def);
		}
	}

	public function animated( name : String, base : Value ) : Value {
		return hrt.prefab.fx.Curve.getCurve(owner, name)?.makeVal() ?? base;
	}

	function mode( def : ParamDef, i : Int ) : ParamMode {
		return (cast owner : IEmitter).getMode(def.name, i);
	}

	// the curve of a Curve Range, its two datas the bounds
	static function rangeCurve( owner : Prefab, name : String ) : hrt.prefab.fx.Curve {
		var c = hrt.prefab.fx.Curve.getCurve(owner, name);
		if( c != null && c.blendMode != hrt.prefab.fx.Curve.CurveBlendMode.Range )
			throw owner.getAbsPath(true) + ': a Curve Range needs a curve in Range mode';
		return c;
	}

	function component( def : ParamDef, i : Int ) : Value {
		return comp(mode(def, i), EmitterParam.curveKey(def, i), def.def[i]);
	}

	public function param( def : ParamDef ) : Value {
		withSlots = def.kind != Emission;
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
