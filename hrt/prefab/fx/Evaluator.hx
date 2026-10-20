package hrt.prefab.fx;

import hrt.prefab.fx.Value;
import hrt.prefab.Curve.CurveBlendMode;

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

	public function getMean(s: SpawnValue) : Float {
		return s.rid < 0 ? getFloat(s.min, 0) : (getFloat(s.min, 0) + getFloat(s.max, 0)) * 0.5;
	}

	public function getSpawn(pidx: Int, s: SpawnValue, time: Float) : Float {
		var v = getFast(pidx, s.min, time);
		return s.rid < 0 ? v : hxd.Math.lerp(v, getFast(pidx, s.max, time), getRandom(pidx, s.rid));
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
			case VCurve(c, from, to): hxd.Math.lerp(from, to, c.getVal(time));
			case VParamCurve(c, from, to): hxd.Math.lerp(from, to, getParamCurve(c, time));
			case VRandomCurve(rid, c, fromMin, fromMax, toMin, toMax):
				var u = getRandom(pidx, rid);
				hxd.Math.lerp(hxd.Math.lerp(fromMin, fromMax, u), hxd.Math.lerp(toMin, toMax, u), c.param == null ? c.getVal(time) : getParamCurve(c, time));
			case VCurveRange(rid, a, aFrom, aTo, b, bFrom, bTo):
				hxd.Math.lerp(hxd.Math.lerp(aFrom, aTo, a.getVal(time)), hxd.Math.lerp(bFrom, bTo, b.getVal(time)), getRandom(pidx, rid));
			case VVector(_), VHsl(_): throw "getFloat: vector value";
		}
	}

	function getParamCurve(c: Curve, time: Float) : Float {
		var p = parameters[c.param] ?? 0.0;
		return c.blendMode == CurveBlendMode.Blend ? hxd.Math.lerp((cast c.children[0] : Curve).getVal(time), (cast c.children[1] : Curve).getVal(time), p) : c.getVal(p);
	}

	public function getSum(val: Value, time: Float) : Float {
		return switch(val) {
			case VZero: 0;
			case VConst(v): v * time;
			case VCurve(c, from, to): from * time + (to - from) * c.getSum(time);
			case VParamCurve(c, from, to):
				var p = parameters[c.param] ?? 0.0;
				var sum = c.blendMode == CurveBlendMode.Blend ? hxd.Math.lerp((cast c.children[0] : Curve).getSum(time), (cast c.children[1] : Curve).getSum(time), p) : c.getSum(p) * time;
				from * time + (to - from) * sum;
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

	public inline function getSpawnVec(pidx: Int, s: Array<SpawnValue>, time: Float, vec: h3d.Vector4) {
		vec.set(getSpawn(pidx, s[0], time), getSpawn(pidx, s[1], time), getSpawn(pidx, s[2], time), 1.0);
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
