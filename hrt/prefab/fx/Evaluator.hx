package hrt.prefab.fx;

import hrt.prefab.fx.Value;

class Evaluator {
	public var parameters: Map<String, Float> = [];
	var randValues : Array<Float> = [];
	var slots = 0;

	public function new() {
	}

	public static function vVal(f: Float) : Value {
		return switch(f) {
			case 0.0: VZero;
			default: VConst(f);
		}
	}

	/** `slots` randoms for each of `count` particles **/
	public function allocRandom(count: Int, slots: Int) {
		this.slots = slots;
		randValues = [for(_ in 0...count * slots) 0.];
	}

	public function resetRandom(rand: hxd.Rand) {
		for(i in 0...randValues.length)
			randValues[i] = (rand.srand() + 1) * 0.5;
	}

	inline function getRandom(pidx: Int, rid: Int) {
		return randValues[pidx * slots + rid];
	}

	public function setAllParameters(params: Array<hrt.prefab.fx.FX.Parameter>) {
		parameters.clear();
		if (params == null)
			return;
		for (p in params) {
			parameters[p.name] = p.def;
		}
	}

	/** The mean of `val` over its random, at time 0 **/
	public function getMean(val: Value) : Float {
		return switch(val) {
			case VRandom(_, min, max): (min + max) * 0.5;
			default: getFloat(val, 0);
		}
	}

	public inline function getFloat(pidx: Int=0, val: Value, time: Float) : Float {
		return getFast(pidx, val, time);
	}

	// no optional argument: HL boxes it
	public function getFast(pidx: Int, val: Value, time: Float) : Float {
		return switch(val) {
			case null, VZero: 0.0;
			case VConst(v): v;
			case VRandom(rid, min, max): hxd.Math.lerp(min, max, getRandom(pidx, rid));
			case VCurve(s, from, to): hxd.Math.lerp(from, to, getShape(s, time));
			case VRandomCurve(rid, s, fromMin, fromMax, toMin, toMax):
				var u = getRandom(pidx, rid);
				hxd.Math.lerp(hxd.Math.lerp(fromMin, fromMax, u), hxd.Math.lerp(toMin, toMax, u), getShape(s, time));
			case VCurveRange(rid, a, b): hxd.Math.lerp(getFast(pidx, a, time), getFast(pidx, b, time), getRandom(pidx, rid));
			case VVector(_), VHsl(_): throw "getFloat: vector value";
		}
	}

	function getShape(s: CurveShape, time: Float) : Float {
		return switch(s) {
			case ShCurve(c): c.getVal(time);
			case ShEasing(e): e.eval(time);
			case ShBlend(a, b, param): hxd.Math.lerp(a.getVal(time), b.getVal(time), parameters[param] ?? 0.0);
			case ShParamRemap(s, param): getShape(s, parameters[param] ?? 0.0);
			case ShValueRemap(s, remap): getShape(s, getFast(0, remap, time));
		}
	}

	public function getSum(val: Value, time: Float) : Float {
		return switch(val) {
			case VZero: 0;
			case VConst(v): v * time;
			case VCurve(s, from, to): from * time + (to - from) * getShapeSum(s, time);
			default: throw "not implemented";
		}
	}

	function getShapeSum(s: CurveShape, time: Float) : Float {
		return switch(s) {
			case ShCurve(c): c.getSum(time);
			case ShBlend(a, b, param): hxd.Math.lerp(a.getSum(time), b.getSum(time), parameters[param] ?? 0.0);
			case ShParamRemap(s, param): getShapeSum(s, parameters[param] ?? 0.0) * time;
			default: throw "not implemented";
		}
	}

	public function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector4) {
		switch(v) {
			case VVector(x, y, z, null):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time), getFloat(pidx, z, time), 1.0);
			case VVector(x, y, z, w):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time), getFloat(pidx, z, time), getFloat(pidx, w, time));
			case VHsl(h, s, l, a):
				vec.makeColor(getFloat(pidx, h, time), getFloat(pidx, s, time), getFloat(pidx, l, time));
				vec.a = getFloat(pidx, a, time);
			case VZero:
				vec.set(0,0,0,1);
			default:
				var f = getFloat(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}

	// inlined, `vec` stays on the stack
	public inline function getFastVec(pidx: Int, v: Value, time: Float, vec: h3d.Vector4) {
		switch(v) {
			case VVector(x, y, z, null):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time), 1.0);
			case VVector(x, y, z, w):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time), getFast(pidx, w, time));
			case VZero:
				vec.set(0,0,0,1);
			default:
				var f = getFast(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}

	public function getVector2(pidx: Int=0, v: Value, time: Float, vec: h2d.col.Point) {
		switch(v) {
			case VVector(x, y, _, _):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time));
			case VZero:
				vec.set(0,0);
			default:
				var f = getFloat(pidx, v, time);
				vec.set(f, f);
		}
		return vec;
	}
}
