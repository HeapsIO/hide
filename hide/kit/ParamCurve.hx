package hide.kit;

#if domkit

typedef ParamRange = { from : Float, to : Float };

/**
	A particle curve of an emitter param, over the particle life: each range is drawn as
	`lerp(from, to, shape(t))`, the first one solid, the others dashed. The keys of `curve`
	are edited in the space of the first range: drag a key, Ctrl + click adds one, right click removes one.
**/
@:access(hrt.prefab.Prefab)
class ParamCurve extends Element {
	public var shape : Float -> Float;
	public var ranges : Array<ParamRange>;
	public var curve : Null<hrt.prefab.Curve>;
	/** Rebuilt when the keys change **/
	public var owner : hrt.prefab.Prefab;

	static inline var SAMPLES = 64;
	static inline var PAD = 4;
	static inline var KEY_SIZE = 6;

	var minY = 0.;
	var maxY = 1.;
	var dragging = false;
	#if js
	var svg : js.html.svg.SVGElement;
	#end

	public function new(parent: Element, id: String, owner: hrt.prefab.Prefab, shape: Float -> Float, ranges: Array<ParamRange>, ?curve: hrt.prefab.Curve) {
		super(parent, id);
		this.owner = owner;
		this.shape = shape;
		this.ranges = ranges;
		this.curve = curve;
	}

	override function makeSelf() {
		#if js
		var doc = js.Browser.document;
		svg = cast doc.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.classList.add("kit-param-curve");
		setupPropLine(null, cast svg);
		new hide.comp.ResizeObserver((_, _) -> refresh()).observe(cast svg);
		svg.addEventListener("pointerdown", onPointerDown);
		svg.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
			e.preventDefault();
			e.stopPropagation();
		});
		#else
		super.makeSelf();
		#end
	}

	function bounds() {
		var s = [for (i in 0...SAMPLES + 1) shape(i / SAMPLES)];
		var lo = hxd.Math.POSITIVE_INFINITY, hi = hxd.Math.NEGATIVE_INFINITY;
		for (r in ranges)
			for (v in s) {
				var y = hxd.Math.lerp(r.from, r.to, v);
				if (y < lo) lo = y;
				if (y > hi) hi = y;
			}
		if (hi - lo < 1e-6) {
			lo -= 0.5;
			hi += 0.5;
		}
		var pad = (hi - lo) * 0.08;
		// the scale stays while a key is dragged, so it doesn't move under the mouse
		minY = dragging ? Math.min(minY, lo - pad) : lo - pad;
		maxY = dragging ? Math.max(maxY, hi + pad) : hi + pad;
		return s;
	}

	inline function toDisplay(v: Float) return hxd.Math.lerp(ranges[0].from, ranges[0].to, v);
	inline function sx(t: Float, w: Float) return PAD + t * (w - PAD * 2);
	inline function sy(v: Float, h: Float) return h - (v - minY) / (maxY - minY) * h;

	public function refresh() {
		#if js
		if (svg == null)
			return;
		var w = svg.clientWidth, h = svg.clientHeight;
		if (w <= 0 || h <= 0)
			return;
		var s = bounds();
		var out = new StringBuf();
		if (minY < 0 && maxY > 0)
			out.add('<line class="zero" x1="0" x2="$w" y1="${sy(0, h)}" y2="${sy(0, h)}"/>');
		for (ri => r in ranges) {
			var d = [for (i in 0...SAMPLES + 1) (i == 0 ? "M" : "L") + sx(i / SAMPLES, w) + " " + sy(hxd.Math.lerp(r.from, r.to, s[i]), h)].join(" ");
			out.add('<path class="${ri == 0 ? "main" : "extreme"}" d="$d"/>');
		}
		if (curve != null)
			for (k in curve.keys)
				out.add('<rect class="key" x="${sx(k.time, w) - KEY_SIZE / 2}" y="${sy(toDisplay(k.value), h) - KEY_SIZE / 2}" width="$KEY_SIZE" height="$KEY_SIZE"/>');
		svg.innerHTML = out.toString();
		#end
	}

	#if js
	function onPointerDown(e: js.html.PointerEvent) {
		if (curve == null || isDisabled())
			return;
		var rect = svg.getBoundingClientRect();
		var w = rect.width, h = rect.height;
		inline function local(e: js.html.PointerEvent) return { x: e.clientX - rect.left, y: e.clientY - rect.top };
		var p = local(e);
		var key = Lambda.find(curve.keys, k -> Math.abs(sx(k.time, w) - p.x) <= KEY_SIZE && Math.abs(sy(toDisplay(k.value), h) - p.y) <= KEY_SIZE);
		var before = hrt.prefab.Diff.deepCopy(curve.save());
		var r = ranges[0];
		var scale = r.to - r.from;
		function time(x: Float) return hxd.Math.clamp((x - PAD) / (w - PAD * 2), 0, 1);
		function value(y: Float) return (maxY - y / h * (maxY - minY) - r.from) / scale;

		e.preventDefault();
		e.stopPropagation();
		if (e.button == 2) {
			if (key != null && curve.keys.length > 1) {
				curve.keys.remove(key);
				commit(before);
			}
			return;
		}
		if (e.button != 0)
			return;
		if (key == null) {
			if (!e.ctrlKey)
				return;
			var t = time(p.x);
			key = curve.addKey(t, Math.abs(scale) > 1e-9 ? value(p.y) : curve.getVal(t), Linear);
			changed();
		}
		var k = key;
		dragging = true;
		svg.setPointerCapture(e.pointerId);
		svg.onpointermove = (e: js.html.PointerEvent) -> {
			var p = local(e);
			var i = curve.keys.indexOf(k);
			var prev = curve.keys[i - 1], next = curve.keys[i + 1];
			k.time = hxd.Math.clamp(time(p.x), prev?.time ?? 0, next?.time ?? 1);
			if (Math.abs(scale) > 1e-9)
				k.value = value(p.y);
			changed();
		}
		svg.onpointerup = (e: js.html.PointerEvent) -> {
			svg.onpointermove = null;
			svg.onpointerup = null;
			svg.releasePointerCapture(e.pointerId);
			dragging = false;
			commit(before);
		}
	}
	#end

	function changed() {
		root.editor.rebuildPrefab(owner);
		refresh();
	}

	function commit(before: Dynamic) {
		changed();
		var c = curve, owner = owner, editor = root.editor;
		var after = hrt.prefab.Diff.deepCopy(c.save());
		editor.recordUndo((isUndo) -> {
			hrt.prefab.fx.AnimEdit.tempLoad(c, hrt.prefab.Diff.deepCopy(isUndo ? before : after));
			editor.rebuildPrefab(owner);
			editor.rebuildInspector();
		}, [c]);
	}
}

#end
