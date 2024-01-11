package hrt.prefab;
using Lambda;

class CurveHandle {
	public var dt: Float;
	public var dv: Float;
	public function new(t, v) {
		this.dt = t;
		this.dv = v;
	}
}

enum abstract CurveKeyMode(Int) {
	var Aligned = 0;
	var Free = 1;
	var Linear = 2;
	var Constant = 3;
}

enum abstract CurveBlendMode(Int) {
	var None = 0;
	var Blend = 1;
	var RandomBlend = 2;
}

class CurveKey {
	public var time: Float;
	public var value: Float;
	public var mode: CurveKeyMode;
	public var prevHandle: CurveHandle;
	public var nextHandle: CurveHandle;
	public function new() {}
}

typedef CurveKeys = Array<CurveKey>;

class Curve extends Prefab {

	@:s public var keyMode : CurveKeyMode = Linear;
	@:c public var keys : CurveKeys = [];
	@:c public var previewKeys : CurveKeys = [];

	@:s public var blendMode : CurveBlendMode = None;
	@:s public var blendFactor : Float = 0;
	@:s public var loop : Bool = false;

	public var maxTime : Float = 5000.;
	public var duration(get, never): Float;
	public var minValue : Float = 0.;
	public var maxValue : Float = 0.;

	public var color : Int;
	public var hidden : Bool = false;
	public var lock : Bool = false;
	public var selected : Bool = false;

	function get_duration() {
		if(keys.length == 0) return 0.0;
		if (blendMode == CurveBlendMode.Blend || blendMode == CurveBlendMode.RandomBlend) {
			var c1:Curve = cast this.children[0];
			var c2:Curve = cast this.children[1];
			return Math.min(c1.duration, c2.duration);
		}
		return keys[keys.length-1].time;
	}

   	public function new(?parent) {
		super(parent);
		this.type = "curve";
	}

	public override function load(o:Dynamic) {
		super.load(o);
		keys = [];
		if(o.keys != null) {
			for(k in (o.keys: Array<Dynamic>)) {
				var nk = new CurveKey();
				nk.time = k.time;
				nk.value = k.value;
				nk.mode = k.mode;
				if(k.prevHandle != null)
					nk.prevHandle = new CurveHandle(k.prevHandle.dt, k.prevHandle.dv);
				if(k.nextHandle != null)
					nk.nextHandle = new CurveHandle(k.nextHandle.dt, k.nextHandle.dv);
				keys.push(nk);
			}
		}
		if( keys.length == 0 ) {
			addKey(0.0, 0.0);
			addKey(1.0, 1.0);
		}
	}

	public override function save() {
		var obj : Dynamic = super.save();
		var keysDat = [];
		for(k in keys) {
			var o = {
				time: k.time,
				value: k.value,
				mode: k.mode
			};
			if(k.prevHandle != null) Reflect.setField(o, "prevHandle", { dv: k.prevHandle.dv, dt: k.prevHandle.dt });
			if(k.nextHandle != null) Reflect.setField(o, "nextHandle", { dv: k.nextHandle.dv, dt: k.nextHandle.dt });
			keysDat.push(o);
		}
		obj.keys = keysDat;
		return obj;
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

	public function addKey(time: Float, ?val: Float, ?mode=null) {
		var index = 0;
		for(ik in 0...keys.length) {
			var key = keys[ik];
			if(time > key.time)
				index = ik + 1;
		}

		if(val == null)
			val = getVal(time);

		var key = new hrt.prefab.Curve.CurveKey();
		key.time = time;
		key.value = val;
		key.mode = mode != null ? mode : (keys[index] != null ? keys[index].mode : keyMode);
		keys.insert(index, key);
		return key;
	}

	public function addPreviewKey(time: Float, val: Float) {
		var key = new hrt.prefab.Curve.CurveKey();
		key.time = time;
		key.value = val;
		previewKeys.push(key);
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

	public function getVal(time: Float) : Float {
		if (blendMode == CurveBlendMode.Blend) {
			var c1 = Std.downcast(this.children[0], Curve);
			var c2 = Std.downcast(this.children[1], Curve);
			var a = c1.getVal(time);
			var b = c2.getVal(time);
			return a + (b - a) * blendFactor;
		}

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
		for(i in 0...numPts) {
			var v = 0.0;
			v = getVal(duration * i/(numPts-1));
			vals.push(v);
		}
		return vals;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('
		<div class="group" name="Parameters">
			<dl>
				<dt>Loop curve</dt><dd><input type="checkbox" field="loop"/></dd>
				<dt>Blend Mode</dt><dd>
					<select class="blendmode-selector" field="blendMode">
						<option value="0">None</option>
						<option value="1">Blend curve</option>
						<option value="2">Random between two curves</option>
					</select>
				</dd>
			</dl>
		</div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});

		var ce = new hide.comp.CurveEditor(ctx.properties.undo, ctx.properties.element, false);
		ce.saveDisplayKey = this.getAbsPath(true);
		ce.curves.push(this);
		ce.refresh();
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "Curve" };
	}
	#end

	public static function getCurve(parent : Prefab, name: String, onlyEnabled=true) {
		for(c in parent.children) {
			if(onlyEnabled && !c.enabled) continue;
			if(c.name != name) continue;
			var curve = c.to(Curve);
			if(curve == null) continue;
			return curve;
		}
		return null;
	}

	public static function getCurves(parent: Prefab, prefix: String) {
		var ret = null;
		for(c in parent.children) {
			if(!c.enabled) continue;
			var idx = c.name.indexOf(".");
			var curvePrefix = (idx >= 0) ? c.name.substr(0, idx) : c.name;
			if(curvePrefix != prefix)
				continue;
			var curve = c.to(Curve);
			if(curve == null) continue;
			if (ret == null) ret = [];
			ret.push(curve);
		}
		return ret;
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

	public static function getVectorValue(curves: Array<Curve>, defVal: Float=0.0, scale: Float=1.0, blendFactor: Float = 1.0, randomValue: Float = 0) : hrt.prefab.fx.Value {
		inline function find(s) {
			return findCurve(curves, s);
		}
		var x = find(".x");
		var y = find(".y");
		var z = find(".z");
		var w = find(".w");

		inline function curveOrVal(c: Curve, defVal: Float) : hrt.prefab.fx.Value {
			if (c == null)
				return VConst(defVal);

			if (c.blendMode == CurveBlendMode.Blend)
				return VBlendCurve(c, blendFactor);

			if (scale != 1.0)
				return VCurveScale(c, scale);

			return VCurve(c);
		}

		return VVector(
			curveOrVal(x, defVal),
			curveOrVal(y, defVal),
			curveOrVal(z, defVal),
			curveOrVal(w, 1.0));
	}

	public static function getColorValue(curves: Array<Curve>) : hrt.prefab.fx.Value {
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

		if(h != null || s != null || l != null) {
			return VHsl(
				h != null ? VCurve(h) : VConst(0.0),
				s != null ? VCurve(s) : VConst(1.0),
				l != null ? VCurve(l) : VConst(1.0),
				a != null ? VCurve(a) : VConst(1.0));
		}

		if(a != null && r == null && g == null && b == null)
			return VCurve(a);

		if(a == null && r == null && g == null && b == null)
			return VOne; // White by default

		return VVector(
			r != null ? VCurve(r) : VConst(1.0),
			g != null ? VCurve(g) : VConst(1.0),
			b != null ? VCurve(b) : VConst(1.0),
			a != null ? VCurve(a) : VConst(1.0));
	}

	static var _ = Library.register("curve", Curve);
}
