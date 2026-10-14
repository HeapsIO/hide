package hrt.prefab.fx;

class Evaluator {
	var randValues : Array<Float>;
	public var parameters: Map<String, Float> = [];
	var stride : Int;

	public function new(?randValues: Array<Float>, stride: Int=0) {
		this.randValues = randValues;
		this.stride = stride;
	}

	public static function vVal(f: Float) : Value {
		return switch(f) {
			case 0.0: VZero;
			default: VConst(f);
		}
	}

	inline function getRandom(pidx: Int, ridx: Int) {
		var i = pidx * stride + ridx;
		return randValues[i];
	}

	public function setAllParameters(params: Array<hrt.prefab.fx.FX.Parameter>) {
		parameters.clear();
		if (params == null)
			return;
		for (p in params) {
			parameters[p.name] = p.def;
		}
	}

	public function getFloat(pidx: Int=0, val: Value, time: Float) : Float {
		return switch(val) {
			case null, VZero: 0.0;
			case VConst(v): v;
			case VCurve(c): c.getVal(time);
			case VRandom(rid, scale, add): getRandom(pidx, rid) * scale + add;
			case VLerp(a, b, t):
				var va = getFloat(pidx, a, time);
				va + (getFloat(pidx, b, time) - va) * getFloat(pidx, t, time);
			case VEasing(e): e.eval(time);
			case VBlendCurves(a, b, blendVar): hxd.Math.lerp(a.getVal(time), b.getVal(time), parameters[blendVar] ?? 0.0);
			case VParamRemap(a, param): getFloat(pidx, a, parameters[param] ?? 0.0);
			case VValueRemap(a, remap): getFloat(pidx, a, getFloat(pidx, remap, time));
			case VVector(_), VHsl(_): throw "getFloat: vector value";
		}
	}

	public function getSum(val: Value, time: Float) : Float {
		return switch(val) {
			case VZero: 0;
			case VConst(v): v * time;
			case VCurve(c): c.getSum(time);
			case VBlendCurves(a, b, blendVar): hxd.Math.lerp(a.getSum(time), b.getSum(time), parameters[blendVar] ?? 0.0);
			case VParamRemap(a, param): getSum(a, parameters[param] ?? 0.0) * time;
			case VLerp(VConst(a), VConst(b), t): a * time + (b - a) * getSum(t, time);
			case VLerp(a, b, t = VConst(_) | VRandom(_)):
				var sa = getSum(a, time);
				sa + (getSum(b, time) - sa) * getFloat(t, 0);
			default: throw "not implemented";
		}
	}

	public inline function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector4) {
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
