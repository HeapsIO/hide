package hrt.prefab.fx;

class Evaluator {
	var randValues : Array<Float>;
	var stride : Int;

	public function new(?randValues: Array<Float>, stride: Int=0) {
		this.randValues = randValues;
		this.stride = stride;
	}

	inline function getRandom(pidx: Int, ridx: Int) {
		var i = pidx * stride + ridx;
		return randValues[i];
	}

	public function getFloat(pidx: Int=0, val: Value, time: Float) : Float {
		if(val == null)
			return 0.0;
		switch(val) {
			case VZero: return 0.0;
			case VOne: return 1.0;
			case VConst(v): return v;
			case VCurve(c): return c.getVal(time);
			case VMultipleCurves(c, factor): return factor;
			case VCurveScale(c, scale): return c.getVal(time) * scale;
			case VRandom(ridx, scale):
				return getRandom(pidx, ridx) * getFloat(pidx, scale, time);
			case VRandomScale(ridx, scale):
				return getRandom(pidx, ridx) * scale;
			case VAddRandCurve(cst, ridx, rscale, c):
				return (cst + getRandom(pidx, ridx) * rscale) * c.getVal(time);
			case VMult(a, b):
				return getFloat(pidx, a, time) * getFloat(pidx, b, time);
			case VAdd(a, b):
				return getFloat(pidx, a, time) + getFloat(pidx, b, time);
			default: 0.0;
		}
		return 0.0;
	}

	public function getSum(val: Value, time: Float) : Float {
		switch(val) {
			case VOne: return time;
			case VConst(v): return v * time;
			case VCurveScale(c, scale): return c.getSum(time) * scale;
			case VCurve(c): return c.getSum(time);
			case VMultipleCurves(c, factor): return c[0].getSum(time);
			case VAdd(a, b):
				return getSum(a, time) + getSum(b, time);
			case VMult(a, b):
			default: throw "Not implemented";
		}
		return 0.0;
	}

	public function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector) {
		switch(v) {
			case VMult(a, b):
				throw "need optimization";
			case VVector(x, y, z, null):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time), getFloat(pidx, z, time), 1.0);
			case VVector(x, y, z, w):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time), getFloat(pidx, z, time), getFloat(pidx, w, time));
			case VHsl(h, s, l, a):
				var hval = getFloat(pidx, h, time);
				var sval = getFloat(pidx, s, time);
				var lval = getFloat(pidx, l, time);
				var aval = getFloat(pidx, a, time);
				vec.makeColor(hval, sval, lval);
				vec.a = aval;
			case VZero:
				vec.set(0,0,0,1);
			case VOne:
				vec.set(1,1,1,1);
			default:
				var f = getFloat(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}
}