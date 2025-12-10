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
			case 1.0: VOne;
			default: VConst(f);
		}
	}

	public static function vMult(a: Value, b: Value) : Value {
		if(a == VZero || b == VZero) return VZero;
		if(a == VOne) return b;
		if(b == VOne) return a;
		switch a {
			case VConst(va):
				return VMult(a, b);
			case VCurve(ca):
				return VMult(a, b);
			case VRandomScale(ri,rscale):
				switch b {
					case VCurve(vb): return VAddRandCurve(0, ri, rscale, vb);
					default:
				}
			case VAdd(va,VRandomScale(ri,rscale)):
				var av = switch (va) {
					case VConst(v): v;
					case VOne: 1.0;
					default: throw "Unsupported";
				}
				switch b {
					case VCurve(vb): return VAddRandCurve(av, ri, rscale, vb);
					default:
				}
			default:
		}
		return VMult(a, b);
	}

	public static function vAdd(a: Value, b: Value) : Value {
		if(a == VZero) return b;
		if(b == VZero) return a;
		switch a {
			case VConst(va):
				switch b {
					case VConst(vb): return VConst(va + vb);
					default:
				}
			default:
		}
		return VAdd(a, b);
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
		if(val == null)
			return 0.0;
		switch(val) {
			case VZero: return 0.0;
			case VOne: return 1.0;
			case VConst(v): return v;
			case VBlend(a,b,v):
				var blend = parameters[v] ?? 0.0;
				return hxd.Math.lerp(getFloat(pidx, a, time), getFloat(pidx, b, time), blend);
			case VCurve(c):  return c.getVal(time);
			case VParamRemap(a, param):
				var time = parameters[param] ?? 0.0;
				return getFloat(pidx, a, time);
			case VValueRemap(a, remap):
				var time = getFloat(pidx, remap, time);
				return getFloat(pidx, a, time);
			case VRandomBetweenCurves(ridx, c):
				{
					var c1 = Std.downcast(c.children[0], Curve);
					var c2 = Std.downcast(c.children[1], Curve);
					var a = c1.getVal(time);
					var b = c2.getVal(time);

					// Should be in [0,1]
					var rand = getRandom(pidx, ridx);
					var min = -1;
					var max = 1;
					var remappedRand = (rand - min) / (max - min);
					return a + (b - a) * remappedRand;
				}
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
			case VCurve(c): return c.getSum(time);
			case VAdd(a, b):
				return getSum(a, time) + getSum(b, time);
			case VParamRemap(a, param):
				var blend = parameters[param] ?? 0.0;
				return getSum(a, blend) * time;
			case VMult(a, VConst(b)), VMult(VConst(b), a): return getSum(a, time) * b;
			case VZero: return 0;
			case VBlend(a,b,v):
				var blend = parameters[v] ?? 0.0;
				return hxd.Math.lerp(getSum(a, time), getSum(b, time), blend);
			default: throw "not implemented";
		}
		return 0.0;
	}

	public function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector4) {
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

	public function getVector2(pidx: Int=0, v: Value, time: Float, vec: h2d.col.Point) {
		switch(v) {
			case VMult(a, b):
				throw "need optimization";
			case VVector(x, y, z, null):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time));
			case VVector(x, y, z, w):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time));
			case VZero:
				vec.set(0,0);
			case VOne:
				vec.set(1,1);
			default:
				var f = getFloat(pidx, v, time);
				vec.set(f, f);
		}
		return vec;
	}
}