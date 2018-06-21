package hide.prefab;
using Lambda;
import hide.prefab.fx.FXScene.Value;
import hide.prefab.fx.FXScene.Evaluator;

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
	public var clampMin : Float = 0.;
	public var clampMax : Float = 0.;
	public var keys : CurveKeys = [];

   	public function new(?parent) {
		super(parent);
		this.type = "curve";
	}

	override function load(o:Dynamic) {
		duration = o.duration;
		keys = o.keys;
		clampMin = o.clampMin;
		clampMax = o.clampMax;
	}

	override function save() {
		return {
			duration: duration,
			clampMin: clampMin,
			clampMax: clampMax,
			keys: keys,
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

	public function getBounds() {
		// TODO: Take bezier handles into account
		var ret = new h2d.col.Bounds();
		for(k in keys) {
			ret.addPos(k.time, k.value);
		}
		return ret;
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

	public function getSum(time: Float) {
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
		for(i in 0...numPts) {
			var v = getVal(duration * i/(numPts-1));
			vals.push(v);
		}
		return vals;
	}

	override function getHideProps() {
		return { icon : "paint-brush", name : "Curve", fileSource : null };
	}


	public static function getCurves(parent: hide.prefab.Prefab, prefix: String) {
		return parent.getAll(hide.prefab.Curve).filter(c -> c.name.split(".")[0] == prefix);
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


	static inline function findCurve(curves: Array<Curve>, suffix: String) {
		return curves.find(c -> StringTools.endsWith(c.name, suffix));
	}

	public static function getColorValue(curves: Array<Curve>, time: Float) : h3d.Vector {
		inline function find(s) {
			return findCurve(curves, s);
		}
		var r = find(".r");
		var g = find(".g");
		var b = find(".b");
		var a = find(".a");
		var h = find(".h");
		var s = find(".s");
		var l = find(".l");

		var col = new h3d.Vector(0, 0, 0, 1);

		if(r != null && g != null && b != null) {
			col.r = r.getVal(time);
			col.g = g.getVal(time);
			col.b = b.getVal(time);
		}
		else {
			var hval = 0.0, sval = 0.0, lval = 0.0;
			if(h != null) hval = h.getVal(time);
			if(s != null) sval = s.getVal(time);
			if(l != null) lval = l.getVal(time);
			col.makeColor(hval, sval, lval);
		}
		if(a != null)
			col.a = a.getVal(time);
		return col;
	}

	// TODO: rename getVectorValue
	public static function getAnimValue(curves: Array<Curve>) : Value {
		inline function find(s) {
			return findCurve(curves, s);
		}
		var x = find(".x");
		var y = find(".y");
		var z = find(".z");
		var w = find(".w");

		return VVector(
			x != null ? VCurve(x) : VConst(0.0),
			y != null ? VCurve(y) : VConst(0.0),
			z != null ? VCurve(z) : VConst(0.0),
			w != null ? VCurve(w) : VConst(1.0));
	}
	
	public static function getColorAnimValue(curves: Array<Curve>) : Value {
		inline function find(s) {
			return findCurve(curves, s);
		}
		
		var r = find(".r");
		var g = find(".g");
		var b = find(".b");
		var a = find(".a");
		var h = find(".h");
		var s = find(".s");
		var l = find(".l");
		
		if(h != null && s != null && l != null) {
			return VHsl(VCurve(h), VCurve(s), VCurve(l), a != null ? VCurve(a) : VConst(1.0));
		}

		return VVector(
			r != null ? VCurve(r) : VConst(1.0),
			g != null ? VCurve(g) : VConst(1.0),
			b != null ? VCurve(b) : VConst(1.0),
			a != null ? VCurve(a) : VConst(1.0));
	}

	static var _ = Library.register("curve", Curve);
}
