package hide.prefab;

typedef CurveHandle = {
	dt: Float,
	dv: Float
}

enum CurveKeyMode {
	Aligned;
	Free;
	Linear;
	Constant;
}

typedef CurveKey = {
	time: Float,
	value: Float,
	?prevHandle: CurveHandle,
	?nextHandle: CurveHandle,
	?mode: CurveKeyMode,
}

typedef CurveKeys = Array<CurveKey>;

class Curve extends Prefab {

	public var duration : Float = 0.;
	public var keys : CurveKeys = [];

   	public function new(?parent) {
		super(parent);
		this.type = "curve";
	}

	override function load(o:Dynamic) {
		duration = o.duration;
		keys = o.keys;
	}

	override function save() {
		return {
			duration: duration,
			keys: keys
		};
	}
	
	static inline function bezier(c0: Float, c1:Float, c2:Float, c3: Float, t:Float) {
		var u = 1 - t;
		return u * u * u * c0 + c1 * 3 * t * u * u + c2 * 3 * t * t * u + t * t * t * c3;
	}

	public function getVal(time: Float) : Float {
		switch(keys.length) {
			case 0: return 0;
			case 1: return keys[0].value;
			default:
		}

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
		if(next == null)
			return cur.value;
		
		var minT = 0.;
		var maxT = 1.;
		var maxDelta = 1./ 25.;

		inline function sampleTime(t) {
			return bezier(cur.time, cur.time + cur.nextHandle.dt, next.time + next.prevHandle.dt, next.time, t);
		}

		inline function sampleVal(t) {
			return bezier(cur.value, cur.value + cur.nextHandle.dv, next.value + next.prevHandle.dv, next.value, t);
		}

		while( maxT - minT > maxDelta ) {
			var t = (maxT + minT) * 0.5;
			var x = sampleTime(t);
			if( x > time )
				maxT = t;
			else
				minT = t;
		}

		var x0 = sampleTime(minT);
		var x1 = sampleTime(maxT);
		var dx = x1 - x0;
		var xfactor = dx == 0 ? 0.5 : (time - x0) / dx;

		var y0 = sampleVal(minT);
		var y1 = sampleVal(maxT);
		var y = y0 + (y1 - y0) * xfactor;
		return y;
	}

	public function sample(numPts: Int) {
		var vals = [];
		for(i in 0...numPts) {
			var v = getVal(duration * i/(numPts-1));
			vals.push(v);
		}
		return vals;
	}
}
