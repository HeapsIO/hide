package hrt.prefab.fx;

import hrt.prefab.fx.Value;

class Evaluator {
	var randValues : Array<Float>;
	public var parameters: Map<String, Float> = [];
	var slots = 0;

	public function new() {
	}

	public static function vVal(f: Float) : Value {
		return switch(f) {
			case 0.0: VZero;
			default: VConst(f);
		}
	}

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

	public function getAtRandom(val: Value, time: Float, u: Float) : Float {
		return eval(val, time, _ -> u);
	}

	public inline function getMean(val: Value, time: Float) : Float {
		return eval(val, time, _ -> 0.5);
	}

	public inline function getFloat(val: Value, time: Float) : Float {
		return getFast(0, val, time);
	}

	// no optional argument, causes boxing on HL
	public inline function getFast(pidx: Int, val: Value, time: Float) : Float {
		return eval(val, time, rid -> getRandom(pidx, rid));
	}

	inline function eval(val: Value, time: Float, rand: Int -> Float) : Float {
		return switch(val) {
			case null, VZero: 0.0;
			case VConst(v): v;
			case VRandom(rid, min, max): hxd.Math.lerp(min, max, rand(rid));
			case VCurve(c): c.getVal(time);
			case VParamCurve(pc): getParamCurve(pc, time);
			case VRandomCurve(rid, c, spread, slope):
				var v = c.getVal(time);
				v + (spread + slope * v) * (rand(rid) * 2 - 1);
			case VRandomParamCurve(rid, pc, spread, slope):
				var v = getParamCurve(pc, time);
				v + (spread + slope * v) * (rand(rid) * 2 - 1);
			case VCurveRange(rid, a, b): hxd.Math.lerp(a.getVal(time), b.getVal(time), rand(rid));
			case VVector(_), VColor(_), VHsl(_): throw "getFloat: vector value";
		}
	}

	function getParamCurve(pc: ParamCurve, time: Float) : Float {
		var p = parameters[pc.param] ?? 0.0;
		return pc.c2 != null ? hxd.Math.lerp(pc.c1.getVal(time), pc.c2.getVal(time), p) : pc.c1.getVal(p);
	}

	public function getSum(val: Value, time: Float) : Float {
		return switch(val) {
			case VZero: 0;
			case VConst(v): v * time;
			case VCurve(c): c.getSum(time);
			case VParamCurve(pc):
				var p = parameters[pc.param] ?? 0.0;
				pc.c2 != null ? hxd.Math.lerp(pc.c1.getSum(time), pc.c2.getSum(time), p) : pc.c1.getVal(p) * time;
			default: throw "not implemented";
		}
	}

	public function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector4) {
		switch(v) {
			case VVector(x, y, z):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time), 1.0);
			case VColor(r, g, b, a):
				vec.set(getFast(pidx, r, time), getFast(pidx, g, time), getFast(pidx, b, time), getFast(pidx, a, time));
			case VHsl(h, s, l, a):
				vec.makeColor(getFast(pidx, h, time), getFast(pidx, s, time), getFast(pidx, l, time));
				vec.a = getFast(pidx, a, time);
			case VZero:
				vec.set(0,0,0,1);
			default:
				var f = getFast(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}

	// inlined, `vec` stays on the stack
	public inline function getFastVec(pidx: Int, v: Value, time: Float, vec: h3d.Vector4) {
		switch(v) {
			case VVector(x, y, z):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time), 1.0);
			case VColor(r, g, b, a):
				vec.set(getFast(pidx, r, time), getFast(pidx, g, time), getFast(pidx, b, time), getFast(pidx, a, time));
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
			case VVector(x, y, _):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time));
			case VZero:
				vec.set(0,0);
			default:
				var f = getFast(pidx, v, time);
				vec.set(f, f);
		}
		return vec;
	}
}
