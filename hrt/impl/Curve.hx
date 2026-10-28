package hrt.impl;

enum abstract CurveKeyMode(Int) {
	var Aligned = 0;
	var Free = 1;
	var Linear = 2;
	var Constant = 3;
}

@:build(hrt.prefab.Macros.buildSerializable())
class CurveHandle {
	@:s public var dv: Float = -1; // Force serialization of 0 values for retrocompat
	@:s public var dt: Float = -1; // Force serialization of 0 values for retrocompat
	public function new(t, v) {
		this.dt = t;
		this.dv = v;
	}
}

@:build(hrt.prefab.Macros.buildSerializable())
class CurveKey {
	@:s public var time: Float = -1; // Force serialization of 0 values for retrocompat
	@:s public var value: Float = -1; // Force serialization of 0 values for retrocompat
	@:s public var mode: CurveKeyMode = Aligned;
	@:s public var prevHandle: CurveHandle;
	@:s public var nextHandle: CurveHandle;
	public function new() {}
}

@:build(hrt.prefab.Macros.buildSerializable())
class Curve {
	#if !editor
	public static var BAKE_ENABLE = true;
	public static var BAKE_MAX_DURATION = 1.0;
	public static var BAKE_RESOLUTION = 128.0;
	#end

	@:s public var keyMode : CurveKeyMode = Linear;
	@:s public var keys : Array<CurveKey> = [];
	@:s public var loop : Bool = false;

	public var duration(get, never): Float;
	function get_duration() {
		if (keys.length == 0) return 0.0;
		return keys[keys.length-1].time;
	}

	#if !editor
	@:c var bake : haxe.ds.Vector<Float> = null;
	@:c var bakeDuration = 0.0;
	#end

	public function new() {
	}

	public static inline function bezier(c0: Float, c1:Float, c2:Float, c3: Float, t:Float) {
		var u = 1 - t;
		return u * u * u * c0 + c1 * 3 * t * u * u + c2 * 3 * t * t * u + t * t * t * c3;
	}

	public function findKey(time: Float, tolerance: Float) {
		var minDist = tolerance;
		var closest = null;
		for(k in keys) {
			var d = hxd.Math.abs(k.time - time);
			if(d < minDist) {
				minDist = d;
				closest = k;
			}
		}
		return closest;
	}

	public function addKey(time: Float, ?val: Float, ?mode=null) {
		var index = 0;
		for(ik in 0...keys.length) {
			var key = keys[ik];
			if(time > key.time)
				index = ik + 1;
		}

		if(val == null)
			val = getVal(time);

		var key = new CurveKey();
		key.time = time;
		key.value = val;
		key.mode = mode != null ? mode : (keys[index] != null ? keys[index].mode : keyMode);
		keys.insert(index, key);
		return key;
	}

	public function getBounds(bounds: h2d.col.Bounds = null) {
		var ret = bounds == null ? new h2d.col.Bounds() : bounds;

		// We always want to show 0,0
		ret.addPos(0.0,0.0);

		for(k in keys) {
			ret.addPos(k.time, k.value);
			if (k.nextHandle != null) {
				ret.addPos(k.time + k.nextHandle.dt, k.value + k.nextHandle.dv);
			}
			if (k.prevHandle != null) {
				ret.addPos(k.time + k.prevHandle.dt, k.value + k.prevHandle.dv);
			}
		}

		return ret;
	}

	#if !editor
	public function bakeValues() {
		if (bake != null || !BAKE_ENABLE || keys.length < 2 || duration <= 0 || duration > BAKE_MAX_DURATION)
			return;

		var numPts = Math.ceil(duration * BAKE_RESOLUTION) + 1;
		var samples = new haxe.ds.Vector<Float>(numPts);
		var prevLoop = loop;
		loop = false; // prevent getVal from looping during baking
		for (i in 0...numPts)
			samples[i] = getVal(i / BAKE_RESOLUTION);
		loop = prevLoop;
		bake = samples;
		bakeDuration = duration;
	}
	#end

	public function getVal(time: Float) : Float {
		#if !editor
		if (bake != null) {
			var duration = bakeDuration;
			var t = time; // HL2 performance hit when modifying func args
			if (loop)
				t %= duration;
			if (t >= 0.0 && t <= duration) {
				var fidx = t * BAKE_RESOLUTION;
				var idx = Math.floor(fidx);
				if (idx >= bake.length - 1)
					return bake[bake.length - 1];
				return hxd.Math.lerp(bake[idx], bake[idx + 1], fidx - idx);
			}
		}
		#end

		switch(keys.length) {
			case 0: return 0;
			case 1: return keys[0].value;
			default:
		}

		if (loop)
			time = time % keys[keys.length-1].time;

		var idx = -1;
		for(ik in 0...keys.length) {
			var key = keys[ik];
			if(time > key.time)
				idx = ik;
		}

		if(idx < 0)
			return keys[0].value;

		var cur = keys[idx];
		var next = keys[idx + 1];
		if(next == null || cur.mode == Constant)
			return cur.value;

		var T = findT(cur, next, time);
		var minT = T.minT;
		var maxT = T.maxT;

		inline function sampleTime(t) {
			return bezier(
				cur.time,
				cur.time + (cur.nextHandle != null ? cur.nextHandle.dt : 0.),
				next.time + (next.prevHandle != null ? next.prevHandle.dt : 0.),
				next.time, t);
		}

		var x0 = sampleTime(minT);
		var x1 = sampleTime(maxT);
		var dx = x1 - x0;
		var xfactor = dx == 0 ? 0.5 : (time - x0) / dx;

		inline function sampleVal(t) {
			return bezier(
				cur.value,
				cur.value + (cur.nextHandle != null ? cur.nextHandle.dv : 0.),
				next.value + (next.prevHandle != null ? next.prevHandle.dv : 0.),
				next.value, t);
		}

		var y0 = sampleVal(minT);
		var y1 = sampleVal(maxT);
		var y = y0 + (y1 - y0) * xfactor;
		return y;
	}

	public function getSum(time: Float) : Float {
		var duration = keys[keys.length-1].time;
		if(loop && time > duration) {
			var cycles = Math.floor(time / duration);
			return getSum(duration) * cycles + getSum(time - cycles);
		}

		var sum = 0.0;
		for(ik in 0...keys.length) {
			var key = keys[ik];
			if(time < key.time)
				break;

			if(ik == 0 && key.time > 0) {
				// Account for start of curve
				sum += key.time * key.value;
			}

			var nkey = keys[ik + 1];
			if(nkey != null) {
				if(time > nkey.time) {
					// Full interval
					sum += key.value * (nkey.time - key.time);
					if(key.mode != Constant)
						sum += 0.5 * (nkey.time - key.time) * (nkey.value - key.value);
				}
				else {
					// Split interval
					sum += key.value * (time - key.time);
					if(key.mode != Constant)
						sum += 0.5 * (time - key.time) * hxd.Math.lerp(key.value, nkey.value, (time - key.time) / (nkey.time - key.time));
				}
			}
			else {
				sum += key.value * (time - key.time);
			}
		}
		return sum;
	}

	public function sample(numPts: Int) {
		var vals = [];
		var duration = this.duration;
		for(i in 0...numPts)
			vals.push(getVal(duration * i/(numPts-1)));
		return vals;
	}

	#if castle
	public function initFromCDB(curve: cdb.Types.Curve) {
		keys = [];
		var nbPoints = Std.int(curve.data.length / 6);
		for (pointIdx in 0...nbPoints) {
			var x = curve.data[pointIdx * 6 + 0];
			var y = curve.data[pointIdx * 6 + 1];
			var prevHandleX = curve.data[pointIdx * 6 + 2];
			var prevHandleY = curve.data[pointIdx * 6 + 3];
			var nextHandleX = curve.data[pointIdx * 6 + 4];
			var nextHandleY = curve.data[pointIdx * 6 + 5];

			var mode : CurveKeyMode = Free;

			if (Math.isNaN(prevHandleX) || prevHandleX == cdb.Types.Curve.HandleData) {
				mode = cast Std.int(prevHandleY);
			}
			else {
				var pt1 = inline new h2d.col.Point(prevHandleX, prevHandleY);
				var pt2 = inline new h2d.col.Point(nextHandleX, nextHandleY);
				pt1.normalize();
				pt2.normalize();
				var dot = pt1.dot(pt2);
				if (Math.abs(dot + 1.0) < 0.01) {
					mode = Aligned;
				}
			}

			var key = addKey(x, y, mode);
			if (mode == Free || mode == Aligned) {
				key.prevHandle = new CurveHandle(Math.isFinite(prevHandleX) ? prevHandleX : 0.0, Math.isFinite(prevHandleY) ? prevHandleY : 0.0);
				key.nextHandle = new CurveHandle(Math.isFinite(nextHandleX) ? nextHandleX : 0.0, Math.isFinite(nextHandleY) ? nextHandleY : 0.0);
			}
		}
	}

	public function toCDB() : cdb.Types.Curve {
		var data : Array<Float>= [];
		for (key in keys) {
			data.push(key.time);
			data.push(key.value);

			switch(key.mode) {
				case Free, Aligned:
					data.push(key.prevHandle?.dt ?? 0.0);
					data.push(key.prevHandle?.dv ?? 0.0);
					data.push(key.nextHandle?.dt ?? 0.0);
					data.push(key.nextHandle?.dv ?? 0.0);
				case Constant, Linear:
					data.push(cdb.Types.Curve.HandleData);
					data.push((cast key.mode:Int));
					data.push(cdb.Types.Curve.HandleData);
					data.push(cdb.Types.Curve.HandleData);
			}
		}
		return cast data;
	}
	#end

	inline function findT(cur: CurveKey, next: CurveKey, time: Float) : {minT: Float, maxT: Float} {
		inline function sampleTime(t) {
			return bezier(
				cur.time,
				cur.time + (cur.nextHandle != null ? cur.nextHandle.dt : 0.),
				next.time + (next.prevHandle != null ? next.prevHandle.dt : 0.),
				next.time, t);
		}

		var minT = 0.;
		var maxT = 1.;
		var maxDelta = 1./ 25.;

		while( maxT - minT > maxDelta ) {
			var t = (maxT + minT) * 0.5;
			var x = sampleTime(t);
			if( x > time )
				maxT = t;
			else
				minT = t;
		}
		return {minT: minT, maxT: maxT};
	}
}
