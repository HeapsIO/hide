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

	static inline function commute(a: Value, b: Value, fn: (Value, Value) -> Null<Value>) : Null<Value> {
		var r = fn(a, b);
		return r != null ? r : fn(b, a);
	}

	public static function vMult(a: Value, b: Value) : Value {
		if(a == VZero || b == VZero) return VZero;
		var r = commute(a, b, (a, b) -> switch [a, b] {
			case [VConst(1.0), _]: b;
			case [VConst(va), VConst(vb)]: VConst(va * vb);
			case [VConst(va), VCurve(c)]: VCurveT(c, va, 0.0);
			case [VConst(va), VCurveT(c, scale, add)]: VCurveT(c, scale * va, add * va);
			case [VRandom(rid, scale, add), VCurve(c)]: VRandMultCurve(rid, scale, add, c);
			case [VRandom(rid, scale, 0.0), VCurveT(c, cscale, 0.0)]: VRandMultCurve(rid, scale * cscale, 0.0, c);
			case [VRandom(rid, scale, add), VBlendCurves(1.0, 0.0, ca, cb, bv)]:
				VRandomBlendCurves(rid, scale, add, ca, cb, bv);
			case [VConst(va), VBlendCurves(scale, add, ca, cb, bv)]:
				VBlendCurves(scale * va, add * va, ca, cb, bv);
			case [VConst(va), VRandomBlendCurves(rid, scale, add, ca, cb, bv)]:
				VRandomBlendCurves(rid, scale * va, add * va, ca, cb, bv);
			default: null;
		});
		return r != null ? r : VMult(a, b);
	}

	public static function vAdd(a: Value, b: Value) : Value {
		if(a == VZero) return b;
		if(b == VZero) return a;
		var r = commute(a, b, (a, b) -> switch [a, b] {
			case [VConst(va), VConst(vb)]: VConst(va + vb);
			case [VConst(va), VRandom(rid, scale, add)]: VRandom(rid, scale, add + va);
			case [VConst(va), VCurve(c)]: VCurveT(c, 1.0, va);
			case [VConst(va), VCurveT(c, scale, add)]: VCurveT(c, scale, add + va);
			case [VRandom(rid, scale, add), VCurve(c)]: VRandAddCurve(rid, scale, add, c);
			case [VRandom(rid, scale, add), VCurveT(c, 1.0, cadd)]: VRandAddCurve(rid, scale, add + cadd, c);
			case [VConst(va), VBlendCurves(scale, add, ca, cb, bv)]: VBlendCurves(scale, add + va, ca, cb, bv);
			default: null;
		});
		return r != null ? r : VAdd(a, b);
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

	public function getFast(pidx: Int, val: Value, time: Float) : Float {
		return switch(val) {
			case null: 0.0;
			case VZero: 0.0;
			case VConst(v): v;
			case VCurve(c): c.getVal(time);
			case VCurveT(c, scale, add): c.getVal(time) * scale + add;
			case VRandom(rid, scale, add): getRandom(pidx, rid) * scale + add;
			case VRandMultCurve(rid, scale, add, c):
				(getRandom(pidx, rid) * scale + add) * c.getVal(time);
			case VRandAddCurve(rid, scale, add, c):
				getRandom(pidx, rid) * scale + add + c.getVal(time);
			case VBlendCurves(scale, add, a, b, blendVar):
				var va = a.getVal(time);
				var vb = b.getVal(time);
				hxd.Math.lerp(va, vb, parameters[blendVar] ?? 0.0) * scale + add;
			case VRandomBlendCurves(rid, scale, add, a, b, blendVar):
				var rnd = getRandom(pidx, rid) * scale + add;
				var va = a.getVal(time);
				var vb = b.getVal(time);
				rnd * hxd.Math.lerp(va, vb, parameters[blendVar] ?? 0.0);
			case VRandomBetweenCurves(rid, a, b):
				var va = a.getVal(time);
				var vb = b.getVal(time);
				va + (vb - va) * ((getRandom(pidx, rid) + 1) * 0.5);
			default:
				throw "getFast: non-flat Value " + Type.enumConstructor(val);
		}
	}

	public function getFloat(pidx: Int=0, val: Value, time: Float) : Float {
		switch(val) {
			case VParamRemap(a, param):
				var time = parameters[param] ?? 0.0;
				return getFloat(pidx, a, time);
			case VValueRemap(a, remap):
				var time = getFloat(pidx, remap, time);
				return getFloat(pidx, a, time);
			case VAdd(a, b):
				return getFloat(pidx, a, time) + getFloat(pidx, b, time);
			case VMult(a, b):
				return getFloat(pidx, a, time) * getFloat(pidx, b, time);
			default:
				return getFast(pidx, val, time);
		}
	}

	public function getSum(val: Value, time: Float) : Float {
		switch(val) {
			case VZero: return 0;
			case VConst(v): return v * time;
			case VCurve(c): return c.getSum(time);
			case VCurveT(c, scale, add): return c.getSum(time) * scale + add * time;
			case VAdd(a, b):
				return getSum(a, time) + getSum(b, time);
			case VParamRemap(a, param):
				var blend = parameters[param] ?? 0.0;
				return getSum(a, blend) * time;
			case VMult(a, VConst(b)), VMult(VConst(b), a): return getSum(a, time) * b;
			case VBlendCurves(scale, add, a, b, blendVar):
				var blend = parameters[blendVar] ?? 0.0;
				return hxd.Math.lerp(a.getSum(time), b.getSum(time), blend) * scale + add * time;
			case VRandomBlendCurves(rid, scale, add, a, b, blendVar):
				var blend = parameters[blendVar] ?? 0.0;
				return (getRandom(0, rid) * scale + add) * hxd.Math.lerp(a.getSum(time), b.getSum(time), blend);
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
			case VZero:
				vec.set(0,0,0,1);
			default:
				var f = getFloat(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}

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
			case VMult(a, b):
				throw "need optimization";
			case VVector(x, y, z, null):
				vec.set(getFloat(pidx, x, time), getFloat(pidx, y, time));
			case VVector(x, y, z, w):
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
