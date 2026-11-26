package hrt.prefab.fx;

import hrt.prefab.fx.Value;


class ParamValues {
	var names : Array<String> = [];
	var values : Array<Float> = [];

	public function new() {
	}

	public function init(params: Array<hrt.prefab.fx.FX.Parameter>) {
		names.resize(0);
		values.resize(0);
		if (params != null)
			for (p in params) {
				names.push(p.name);
				values.push(p.def);
			}
	}

	public function indexOf(name: String) {
		for(i in 0...names.length)
			if(names[i] == name)
				return i;
		return -1;
	}

	public inline function getAt(i: Int) : Float {
		return values[i];
	}

	public inline function setAt(i: Int, v: Float) {
		values[i] = v;
	}

	public function exists(name: String) {
		return indexOf(name) >= 0;
	}

	public function get(name: String) : Float {
		var i = indexOf(name);
		return i < 0 ? 0.0 : values[i];
	}

	public function set(name: String, v: Float) {
		var i = indexOf(name);
		if(i < 0) {
			names.push(name);
			values.push(v);
		} else
			values[i] = v;
	}

	public function clear() {
		init(null);
	}

	public function keys() {
		return names.iterator();
	}

	public function keyValueIterator() : KeyValueIterator<String, Float> {
		return [for(i in 0...names.length) { key: names[i], value: values[i] }].iterator();
	}
}

class Evaluator {
	public var parameters = new ParamValues();

	/*
		The randoms of the particles: a particle has a seed (its index), its random `rid` is in one table shared by all
		emitters, at seed + rid * RAND_STEP. A fast lookup and nothing per emitter; the quality doesn't matter, it's visual.
	*/
	public static inline var RAND_SIZE = 4096;
	// odd: the randoms of a particle are far apart in the table
	public static inline var RAND_STEP = 0x9E3779B1;
	public static var RAND : haxe.ds.Vector<Float> = makeRand();

	static function makeRand() {
		var r = new hxd.Rand(0x5EED);
		var v = new haxe.ds.Vector<Float>(RAND_SIZE);
		for(i in 0...RAND_SIZE)
			v[i] = (r.srand() + 1) * 0.5;
		return v;
	}

	/** The seed of a new particle, from the random stream of its emitter **/
	public static inline function particleSeed(rand: hxd.Rand) {
		return rand.random(RAND_SIZE);
	}

	public function new() {
	}

	public static function vVal(f: Float) : Value {
		return switch(f) {
			case 0.0: VZero;
			default: VConst(f);
		}
	}

	inline function getRandom(pidx: Int, rid: Int) {
		return RAND[(pidx + rid * RAND_STEP) & (RAND_SIZE - 1)];
	}

	public function setAllParameters(params: Array<hrt.prefab.fx.FX.Parameter>) {
		parameters.init(params);
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
			case VVector(_), VGradient(_): throw "getFloat: vector value";
		}
	}

	inline function paramValue(pc: ParamCurve) : Float {
		#if editor
		return parameters.get(pc.param);
		#else
		return parameters.getAt(pc.idx);
		#end
	}

	function getParamCurve(pc: ParamCurve, time: Float) : Float {
		var p = paramValue(pc);
		return pc.c2 != null ? hxd.Math.lerp(pc.c1.getVal(time), pc.c2.getVal(time), p) : pc.c1.getVal(p);
	}

	public function getSum(val: Value, time: Float) : Float {
		return switch(val) {
			case VZero: 0;
			case VConst(v): v * time;
			case VCurve(c): c.getSum(time);
			case VParamCurve(pc):
				var p = paramValue(pc);
				pc.c2 != null ? hxd.Math.lerp(pc.c1.getSum(time), pc.c2.getSum(time), p) : pc.c1.getVal(p) * time;
			default: throw "not implemented";
		}
	}

	public function getVector(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector4) {
		switch(v) {
			case VVector(x, y, z):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time), 1.0);
			case VGradient(g):
				g.eval(time, vec);
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
			case VZero:
				vec.set(0,0,0,1);
			default:
				var f = getFast(pidx, v, time);
				vec.set(f, f, f, 1.0);
		}
		return vec;
	}

	public function getVector3(pidx: Int=0, v: Value, time: Float, vec: h3d.Vector) {
		switch(v) {
			case VVector(x, y, z), VColor(x, y, z, _):
				vec.set(getFast(pidx, x, time), getFast(pidx, y, time), getFast(pidx, z, time));
			case VHsl(h, s, l, _):
				vec.makeColor(getFast(pidx, h, time), getFast(pidx, s, time), getFast(pidx, l, time));
			case VZero:
				vec.set(0,0,0);
			default:
				var f = getFast(pidx, v, time);
				vec.set(f, f, f);
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
