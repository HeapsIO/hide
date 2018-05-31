package hide.prefab;
using Lambda;

typedef CurveHandle = {
	dt: Float,
	dv: Float
}

@:enum abstract CurveKeyMode(Int) {
	var Aligned = 0;
	var Free = 1;
	var Linear = 2;
	var Constant = 3;
}

typedef CurveKey = {
	time: Float,
	value: Float,
	mode: CurveKeyMode,	
	?prevHandle: CurveHandle,
	?nextHandle: CurveHandle,
}

typedef CurveKeys = Array<CurveKey>;

class Curve extends Prefab {

	public var duration : Float = 0.; // TODO: optional?
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

	public function addKey(time: Float, ?val: Float) {
		var index = 0;
		for(ik in 0...keys.length) {
			var key = keys[ik];
			if(time > key.time)
				index = ik + 1;
		}

		if(val == null)
			val = getVal(time);

		var key : hide.prefab.Curve.CurveKey = {
			time: time,
			value: val,
			mode: keys[index] != null ? keys[index].mode : Aligned
		};
		keys.insert(index, key);
		return key;
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
		if(next == null || cur.mode == Constant)
			return cur.value;
		
		var minT = 0.;
		var maxT = 1.;
		var maxDelta = 1./ 25.;

		inline function sampleTime(t) {
			return bezier(
				cur.time,
				cur.time + (cur.nextHandle != null ? cur.nextHandle.dt : 0.),
				next.time + (next.prevHandle != null ? next.prevHandle.dt : 0.),
				next.time, t);
		}

		inline function sampleVal(t) {
			return bezier(
				cur.value,
				cur.value + (cur.nextHandle != null ? cur.nextHandle.dv : 0.),
				next.value + (next.prevHandle != null ? next.prevHandle.dv : 0.),
				next.value, t);
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

	public static function getGroups(curves: Array<Curve>) {
		var groups : Array<{name: String, items: Array<Curve>}> = [];
		for(c in curves) {
			var prefix = c.name.split(".")[0];
			var g = groups.find(g -> g.name == prefix);
			if(g == null) {
				groups.push({
					name: prefix,
					items: [c]
				});
			}
			else {
				g.items.push(c);
			}
		}
		return groups;
	}

	public static function getColorValue(curves: Array<Curve>, time: Float) : h3d.Vector {
		inline function findCurve(suffix: String) {
			return curves.find(c -> StringTools.endsWith(c.name, suffix));
		}
		
		var r = findCurve(".r");
		var g = findCurve(".g");
		var b = findCurve(".b");
		var a = findCurve(".a");
		var h = findCurve(".h");
		var s = findCurve(".s");
		var l = findCurve(".l");

		var col = new h3d.Vector(0, 0, 0, 1);

		if(r != null && g != null && b != null) {
			col.r = r.getVal(time);
			col.g = g.getVal(time);
			col.b = b.getVal(time);
			if(a != null) {
				col.a = a.getVal(time);
			}
		}
		else {
			var hval = 0.0, sval = 0.0, lval = 0.0;
			if(h != null) {
				hval = h.getVal(time);
			}
			col.makeColor(hval, sval, lval);
		}
		return col;
	}

	override function getHideProps() {
		return { icon : "paint-brush", name : "Curve", fileSource : null };
	}

	static var _ = Library.register("curve", Curve);
}
