package hide.kit;

#if domkit

typedef ParamRange = { from : Float, to : Float };

/**
	A particle curve of an emitter param, over the particle life: each range is drawn as
	`lerp(from, to, shape(t))`, the first one solid, the others dashed. The keys of `curve`
	are edited in the space of the first range: drag a key, Ctrl + click adds one, right click removes one.
	The view shows at least 0 to 1 vertically, framed on the curve when built or with F, zoomed with
	Shift + wheel or the +/- buttons.
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
	#if js
	var svg : js.html.svg.SVGElement;
	#end

	public function new(parent: Element, id: String, owner: hrt.prefab.Prefab, shape: Float -> Float, ranges: Array<ParamRange>, ?curve: hrt.prefab.Curve) {
		super(parent, id);
		this.owner = owner;
		this.shape = shape;
		this.ranges = ranges;
		this.curve = curve;
		frame();
	}

	override function makeSelf() {
		#if js
		var doc = js.Browser.document;
		var e = doc.createElement("kit-param-curve");
		e.tabIndex = 0;
		svg = cast doc.createElementNS("http://www.w3.org/2000/svg", "svg");
		e.appendChild(svg);
		var buttons = doc.createElement("kit-zoom");
		for (b in [{ label: "+", factor: 0.5 }, { label: "-", factor: 2. }]) {
			var button = doc.createSpanElement();
			button.innerText = b.label;
			button.title = "Zoom " + (b.factor < 1 ? "in" : "out") + " vertically (Shift + wheel, F to frame)";
			button.onclick = () -> zoom(b.factor);
			buttons.appendChild(button);
		}
		e.appendChild(buttons);
		setupPropLine(null, cast e);
		new hide.comp.ResizeObserver((_, _) -> refresh()).observe(cast svg);
		svg.addEventListener("pointerdown", onPointerDown);
		svg.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
			e.preventDefault();
			e.stopPropagation();
		});
		svg.addEventListener("wheel", (e: js.html.WheelEvent) -> {
			if (!e.shiftKey)
				return;
			e.preventDefault();
			e.stopPropagation();
			zoom(e.deltaY + e.deltaX < 0 ? 1 / 1.125 : 1.125);
		});
		e.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.key != "f" || e.ctrlKey)
				return;
			e.preventDefault();
			e.stopPropagation();
			frame();
			refresh();
		});
		#else
		super.makeSelf();
		#end
	}

	function samples() return [for (i in 0...SAMPLES + 1) shape(i / SAMPLES)];

	/** The view on the curve and 0 to 1 **/
	function frame() {
		minY = 0;
		maxY = 1;
		for (r in ranges)
			for (v in samples()) {
				var y = hxd.Math.lerp(r.from, r.to, v);
				minY = Math.min(minY, y);
				maxY = Math.max(maxY, y);
			}
	}

	/** Scales the view from 0, keeping 0 to 1 in it **/
	function zoom(factor: Float) {
		minY = Math.min(minY * factor, 0);
		maxY = Math.max(maxY * factor, 1);
		refresh();
	}

	inline function toDisplay(v: Float) return hxd.Math.lerp(ranges[0].from, ranges[0].to, v);
	inline function sx(t: Float, w: Float) return PAD + t * (w - PAD * 2);
	inline function sy(v: Float, h: Float) return h - PAD - (v - minY) / (maxY - minY) * (h - PAD * 2);

	public function refresh() {
		#if js
		if (svg == null)
			return;
		var w = svg.clientWidth, h = svg.clientHeight;
		if (w <= 0 || h <= 0)
			return;
		var s = samples();
		var out = new StringBuf();
		var step = 0.1;
		while ((maxY - minY) / step > 10)
			step *= 2;
		for (i in Math.ceil(minY / step)...Math.floor(maxY / step) + 1) {
			var y = sy(i * step, h);
			out.add('<line class="${i == 0 ? "zero" : "grid"}" x1="0" x2="$w" y1="$y" y2="$y"/>');
		}
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
		function value(y: Float) return (minY + (h - PAD - y) / (h - PAD * 2) * (maxY - minY) - r.from) / scale;

		e.preventDefault();
		e.stopPropagation();
		svg.parentElement.focus();
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
		root.editor.recordPrefabUndo(curve, before, owner);
	}
}

#end
