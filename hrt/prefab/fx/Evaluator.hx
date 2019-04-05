package hide.prefab.fx;

class Evaluator {
	var randValues : Array<Float> = [];
	var random: hxd.Rand;

	public function new(random: hxd.Rand) {
		this.random = random;
	}

	public function getFloat(val: Value, time: Float) : Float {
		if(val == null)
			return 0.0;
		switch(val) {
			case VZero: return 0.0;
			case VConst(v): return v;
			case VCurve(c): return c.getVal(time);
			case VCurveScale(c, scale): return c.getVal(time) * scale;
			case VRandom(idx, scale):
				var len = randValues.length;
				while(idx >= len) {
					randValues.push(random.srand());
					++len;
				}
				return randValues[idx] * getFloat(scale, time);
			case VMult(a, b):
				return getFloat(a, time) * getFloat(b, time);
			case VAdd(a, b):
				return getFloat(a, time) + getFloat(b, time);
			default: 0.0;
		}
		return 0.0;
	}

	public function getSum(val: Value, time: Float) : Float {
		switch(val) {
			case VConst(v): return v * time;
			case VCurveScale(c, scale): return c.getSum(time) * scale;
			case VAdd(a, b):
				return getSum(a, time) + getSum(b, time);
			default: 0.0;
		}
		return 0.0;
	}

	public function getVector(v: Value, time: Float, ?vec: h3d.Vector) : h3d.Vector {
		if(vec == null)
			vec = new h3d.Vector();
		switch(v) {
			case VMult(a, b):
				var av = getVector(a, time);
				var bv = getVector(b, time);
				vec.set(av.x * bv.x, av.y * bv.y, av.z * bv.z, av.w * bv.w);
			case VVector(x, y, z, null):
				vec.set(getFloat(x, time), getFloat(y, time), getFloat(z, time), 1.0);
			case VVector(x, y, z, w):
				vec.set(getFloat(x, time), getFloat(y, time), getFloat(z, time), getFloat(w, time));
			case VHsl(h, s, l, a):
				var hval = getFloat(h, time);
				var sval = getFloat(s, time);
				var lval = getFloat(l, time);
				var aval = getFloat(a, time);
				vec.makeColor(hval, sval, lval);
				vec.a = aval;
			default:
				var f = getFloat(v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}
}