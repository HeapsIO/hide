package hide.kit;

#if domkit

import hrt.prefab.Curve.CurveKeyMode;

typedef ParamRange = { from : Float, to : Float };

/**
	A particle curve of an emitter param, over the particle life: each range is drawn as
	`lerp(from, to, shape(t))`, the first one solid, the others dashed, as the `blends` (the curves of a blend,
	in the first range). The keys of `curve`
	are edited in the space of the first range, as in the curve editor of the timeline: drag a key or a
	tangent handle (Ctrl: round, Shift: keep the time, Alt: keep the value), Ctrl + click adds a key,
	Delete removes the selected one, right click on a key sets its mode, double click edits its time and value.
	The view shows at least 0 to 1 vertically, framed on the curve when built or with F, zoomed around its
	center with Shift + wheel or the +/- buttons.
**/
@:access(hrt.prefab.Prefab)
class ParamCurve extends Element {
	public var shape : Float -> Float;
	public var ranges : Array<ParamRange>;
	public var curve : Null<hrt.prefab.Curve>;
	public var blends : Array<Float -> Float>;
	/** Rebuilt when the keys change **/
	public var owner : hrt.prefab.Prefab;

	static inline var SAMPLES = 64;
	static inline var PAD = 4;
	static inline var KEY_SIZE = 6;
	static inline var HANDLE_SIZE = 3;
	/** The grid lines at most, its step is the smallest of 1, 2, 5, 10, 20... that keeps under it **/
	static inline var MAX_LINES = 6;

	var minY = 0.;
	var maxY = 1.;
	var selected : Null<hrt.prefab.Curve.CurveKey>;
	var lastClick : Null<{ key: hrt.prefab.Curve.CurveKey, time: Float }>;
	#if js
	var svg : js.html.svg.SVGElement;
	#end

	public function new(parent: Element, id: String, owner: hrt.prefab.Prefab, shape: Float -> Float, ranges: Array<ParamRange>, ?curve: hrt.prefab.Curve, ?blends: Array<Float -> Float>) {
		super(parent, id);
		this.owner = owner;
		this.shape = shape;
		this.ranges = ranges;
		this.curve = curve;
		this.blends = blends ?? [];
		cssClass = "kit-param-curve-line";
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
		// no label: the curve takes the width of the line
		setupPropLine(null, cast e, false);
		new hide.comp.ResizeObserver((_, _) -> refresh()).observe(cast svg);
		svg.addEventListener("pointerdown", onPointerDown);
		svg.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
			e.preventDefault();
			e.stopPropagation();
			onContextMenu(e);
		});
		svg.addEventListener("wheel", (e: js.html.WheelEvent) -> {
			if (!e.shiftKey)
				return;
			e.preventDefault();
			e.stopPropagation();
			zoom(e.deltaY + e.deltaX < 0 ? 1 / 1.125 : 1.125);
		});
		e.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.ctrlKey)
				return;
			switch (e.key) {
				case "f":
					frame();
					refresh();
				case "Delete" if (selected != null && curve != null):
					deleteKey(selected);
				default:
					return;
			}
			e.preventDefault();
			e.stopPropagation();
		});
		#else
		super.makeSelf();
		#end
	}

	function samples(?f: Float -> Float) return [for (i in 0...SAMPLES + 1) (f ?? shape)(i / SAMPLES)];

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
		for (b in blends)
			for (v in samples(b)) {
				var y = toDisplay(v);
				minY = Math.min(minY, y);
				maxY = Math.max(maxY, y);
			}
	}

	/** New ranges, the view framed on them **/
	public function setRanges(ranges: Array<ParamRange>) {
		this.ranges = ranges;
		frame();
		refresh();
	}

	/** Scales the view around its center, keeping 0 to 1 in it **/
	function zoom(factor: Float) {
		var center = (minY + maxY) * 0.5, half = (maxY - minY) * 0.5 * factor;
		minY = Math.min(center - half, 0);
		maxY = Math.max(center + half, 1);
		refresh();
	}

	inline function toDisplay(v: Float) return hxd.Math.lerp(ranges[0].from, ranges[0].to, v);
	inline function sx(t: Float, w: Float) return PAD + t * (w - PAD * 2);
	inline function sy(v: Float, h: Float) return h - PAD - (v - minY) / (maxY - minY) * (h - PAD * 2);

	/** The step of the grid: an integer, 1, 2 or 5 times a power of 10 **/
	function gridStep() {
		var step = 1., i = 0;
		while ((maxY - minY) / step > MAX_LINES)
			step = [1, 2, 5][++i % 3] * Math.pow(10, Std.int(i / 3));
		return step;
	}

	public function refresh() {
		#if js
		if (svg == null)
			return;
		var w = svg.clientWidth, h = svg.clientHeight;
		if (w <= 0 || h <= 0)
			return;
		var s = samples();
		var out = new StringBuf();
		var step = gridStep();
		for (i in Math.ceil(minY / step)...Math.floor(maxY / step) + 1) {
			var y = sy(i * step, h);
			out.add('<line class="${i == 0 ? "zero" : "grid"}" x1="0" x2="$w" y1="$y" y2="$y"/>');
			// the label above its line, below it at the top of the view
			out.add('<text x="2" y="${y - 2 < 9 ? y + 9 : y - 2}">${i * step}</text>');
		}
		function path(s: Array<Float>, r: ParamRange, cls: String)
			out.add('<path class="$cls" d="${[for (i in 0...SAMPLES + 1) (i == 0 ? "M" : "L") + sx(i / SAMPLES, w) + " " + sy(hxd.Math.lerp(r.from, r.to, s[i]), h)].join(" ")}"/>');
		for (b in blends)
			path(samples(b), ranges[0], "extreme");
		for (ri => r in ranges)
			path(s, r, ri == 0 ? "main" : "extreme");
		if (curve != null) {
			if (!curve.keys.contains(selected))
				selected = null;
			if (selected != null)
				for (hd in handles(selected)) {
					var x = sx(selected.time + hd.h.dt, w), y = sy(toDisplay(selected.value + hd.h.dv), h);
					out.add('<line class="tangent" x1="${sx(selected.time, w)}" y1="${sy(toDisplay(selected.value), h)}" x2="$x" y2="$y"/>');
					out.add('<circle class="handle" cx="$x" cy="$y" r="$HANDLE_SIZE"/>');
				}
			for (k in curve.keys)
				out.add('<rect class="key${k == selected ? " selected" : ""}" x="${sx(k.time, w) - KEY_SIZE / 2}" y="${sy(toDisplay(k.value), h) - KEY_SIZE / 2}" width="$KEY_SIZE" height="$KEY_SIZE"/>');
		}
		svg.innerHTML = out.toString();
		#end
	}

	/** The tangent handles of `k` that are shown and edited: none for a linear or constant key **/
	static function handles(k: hrt.prefab.Curve.CurveKey) : Array<{ h: hrt.prefab.Curve.CurveHandle, next: Bool }> {
		if (k.mode == CurveKeyMode.Linear || k.mode == CurveKeyMode.Constant)
			return [];
		return [for (next in [false, true]) {
			var h = next ? k.nextHandle : k.prevHandle;
			if (h != null) { h: h, next: next };
		}];
	}

	/** Gives `k` the handles of its mode, as the curve editor of the timeline does **/
	function fixKey(k: hrt.prefab.Curve.CurveKey) {
		var i = curve.keys.indexOf(k);
		var prev = curve.keys[i - 1], next = curve.keys[i + 1];
		switch (k.mode) {
			case Aligned, Free:
				k.prevHandle ??= new hrt.prefab.Curve.CurveHandle(prev != null ? (prev.time - k.time) / 3 : -0.1, 0);
				k.nextHandle ??= new hrt.prefab.Curve.CurveHandle(next != null ? (next.time - k.time) / 3 : 0.1, 0);
			case Linear, Constant:
				k.prevHandle = null;
				k.nextHandle = null;
		}
	}

	#if js
	/** The view mapping of the svg: screen positions to curve time and value, and back **/
	function mapping() {
		var rect = svg.getBoundingClientRect();
		var w = rect.width, h = rect.height;
		var r = ranges[0];
		var scale = r.to - r.from;
		return {
			rect: rect,
			w: w,
			h: h,
			/** Keys can only move in time when the range is empty **/
			flat: Math.abs(scale) <= 1e-9,
			local: (e: js.html.MouseEvent) -> { x: e.clientX - rect.left, y: e.clientY - rect.top },
			time: (x: Float) -> (x - PAD) / (w - PAD * 2),
			value: (y: Float) -> (minY + (h - PAD - y) / (h - PAD * 2) * (maxY - minY) - r.from) / scale,
		};
	}

	function keyAt(x: Float, y: Float, w: Float, h: Float) {
		return Lambda.find(curve.keys, k -> Math.abs(sx(k.time, w) - x) <= KEY_SIZE && Math.abs(sy(toDisplay(k.value), h) - y) <= KEY_SIZE);
	}

	function handleAt(x: Float, y: Float, w: Float, h: Float) {
		if (selected == null)
			return null;
		return Lambda.find(handles(selected), hd -> Math.abs(sx(selected.time + hd.h.dt, w) - x) <= HANDLE_SIZE + 2 && Math.abs(sy(toDisplay(selected.value + hd.h.dv), h) - y) <= HANDLE_SIZE + 2);
	}

	function onPointerDown(e: js.html.PointerEvent) {
		if (curve == null || isDisabled())
			return;
		var m = mapping();
		var p = m.local(e);
		var before = hrt.prefab.Diff.deepCopy(curve.save());

		e.preventDefault();
		e.stopPropagation();
		svg.parentElement.focus();
		if (e.button != 0)
			return;

		var hd = handleAt(p.x, p.y, m.w, m.h);
		if (hd != null) {
			dragHandle(e, selected, hd.h, hd.next, before);
			return;
		}
		var key = keyAt(p.x, p.y, m.w, m.h);
		if (key == null) {
			if (!e.ctrlKey) {
				selected = null;
				refresh();
				return;
			}
			var t = hxd.Math.clamp(m.time(p.x), 0, 1);
			key = curve.addKey(t, m.flat ? curve.getVal(t) : m.value(p.y), curve.keyMode);
			fixKey(key);
		} else {
			// the svg is redrawn by the first click: the double click is found here, not by a dblclick event
			var now = haxe.Timer.stamp();
			if (lastClick != null && lastClick.key == key && now - lastClick.time < 0.4) {
				lastClick = null;
				editKey(key, e.clientX, e.clientY);
				return;
			}
			lastClick = { key: key, time: now };
		}
		selected = key;
		changed();
		var k = key, startTime = key.time, startValue = key.value;
		drag(e, (e) -> {
			var p = m.local(e);
			var i = curve.keys.indexOf(k);
			var prev = curve.keys[i - 1], next = curve.keys[i + 1];
			var t = m.time(p.x), v = m.flat ? k.value : m.value(p.y);
			if (e.ctrlKey) {
				t = Math.round(t * 10) / 10;
				if (!m.flat)
					v = (Math.round(toDisplay(v) * 10) / 10 - ranges[0].from) / (ranges[0].to - ranges[0].from);
			}
			k.time = e.shiftKey ? startTime : hxd.Math.clamp(t, prev?.time ?? 0, next?.time ?? 1);
			k.value = e.altKey ? startValue : v;
			changed();
		}, () -> commit(before));
	}

	/** The menu of a key: its mode, its time and value, delete. Elsewhere: add a key **/
	function onContextMenu(e: js.html.MouseEvent) {
		if (curve == null || isDisabled())
			return;
		var m = mapping();
		var p = m.local(e);
		var key = keyAt(p.x, p.y, m.w, m.h);
		if (key != null) {
			selected = key;
			refresh();
			keyMenu(e, key);
			return;
		}
		hide.comp.ContextMenu.createFromPoint(e.clientX, e.clientY, [{ label: "Add key", keys: "Ctrl + click", click: () -> {
			var t = hxd.Math.clamp(m.time(p.x), 0, 1);
			var before = hrt.prefab.Diff.deepCopy(curve.save());
			selected = curve.addKey(t, m.flat ? curve.getVal(t) : m.value(p.y), curve.keyMode);
			fixKey(selected);
			commit(before);
		} }]);
	}

	/** Drags `handle` of `k`, the other one following it in the Aligned mode, opposite and of the same length on screen **/
	function dragHandle(e: js.html.PointerEvent, k: hrt.prefab.Curve.CurveKey, handle: hrt.prefab.Curve.CurveHandle, next: Bool, before: Dynamic) {
		var m = mapping();
		var other = next ? k.prevHandle : k.nextHandle;
		inline function kx() return sx(k.time, m.w);
		inline function ky() return sy(toDisplay(k.value), m.h);
		var otherLength = other == null ? 0. : hxd.Math.distance(sx(k.time + other.dt, m.w) - kx(), sy(toDisplay(k.value + other.dv), m.h) - ky());
		drag(e, (e) -> {
			var p = m.local(e);
			// a handle stays on its side of the key
			var x = next ? Math.max(p.x, kx()) : Math.min(p.x, kx());
			handle.dt = m.time(x) - k.time;
			if (!m.flat)
				handle.dv = m.value(p.y) - k.value;
			if (k.mode == CurveKeyMode.Aligned && other != null && !m.flat) {
				var dx = x - kx(), dy = p.y - ky();
				var len = hxd.Math.distance(dx, dy);
				if (len > 1e-6) {
					var ox = kx() - dx / len * otherLength, oy = ky() - dy / len * otherLength;
					other.dt = m.time(ox) - k.time;
					other.dv = m.value(oy) - k.value;
				}
			}
			changed();
		}, () -> commit(before));
	}

	function drag(e: js.html.PointerEvent, move: js.html.PointerEvent -> Void, end: () -> Void) {
		svg.setPointerCapture(e.pointerId);
		svg.onpointermove = move;
		svg.onpointerup = (e: js.html.PointerEvent) -> {
			svg.onpointermove = null;
			svg.onpointerup = null;
			svg.releasePointerCapture(e.pointerId);
			end();
		}
	}

	function keyMenu(e: js.html.MouseEvent, k: hrt.prefab.Curve.CurveKey) {
		var items : Array<hrt.ui.HuiMenu.MenuItem> = [for (mode in [CurveKeyMode.Aligned, CurveKeyMode.Free, CurveKeyMode.Linear, CurveKeyMode.Constant]) {
			label: Std.string(["Aligned", "Free", "Linear", "Constant"][(cast mode : Int)]),
			radio: () -> k.mode == mode,
			click: () -> {
				var before = hrt.prefab.Diff.deepCopy(curve.save());
				k.mode = mode;
				curve.keyMode = mode;
				fixKey(k);
				commit(before);
			},
		}];
		items.push({ isSeparator: true });
		items.push({ label: "Edit time and value", click: () -> editKey(k, e.clientX, e.clientY) });
		items.push({ label: "Delete key", keys: "Delete", click: () -> deleteKey(k), enabled: curve.keys.length > 1 });
		hide.comp.ContextMenu.createFromPoint(e.clientX, e.clientY, items);
	}

	/** A popup with the time and the value (as displayed) of `k` **/
	function editKey(k: hrt.prefab.Curve.CurveKey, x: Float, y: Float) {
		var popup = new hide.comp.Popup(new hide.Element(js.Browser.document.body), false);
		var content = new hide.Element('<div class="keyPopup">
			<div class="line"><label>Time</label><input class="t" type="number" step="0.05"/></div>
			<div class="line"><label>Value</label><input class="v" type="number" step="0.1"/></div>
		</div>').appendTo(popup.element);
		popup.position = Inside;
		popup.offsetX = x + 8;
		popup.offsetY = y - 20;
		popup.onClose = () -> popup.element.remove();
		var r = ranges[0];
		var flat = Math.abs(r.to - r.from) <= 1e-9;
		var t = content.find(".t"), v = content.find(".v");
		t.val(hxd.Math.fmt(k.time));
		v.val(hxd.Math.fmt(toDisplay(k.value)));
		v.prop("disabled", flat);
		function set(f: Float -> Void, input: hide.Element) {
			var f2 = Std.parseFloat(input.val());
			if (Math.isNaN(f2))
				return;
			var before = hrt.prefab.Diff.deepCopy(curve.save());
			f(f2);
			commit(before);
		}
		t.change((_) -> set(f -> {
			var i = curve.keys.indexOf(k);
			k.time = hxd.Math.clamp(f, curve.keys[i - 1]?.time ?? 0, curve.keys[i + 1]?.time ?? 1);
		}, t));
		v.change((_) -> set(f -> k.value = (f - r.from) / (r.to - r.from), v));
		t.focus();
	}
	#end

	function deleteKey(k: hrt.prefab.Curve.CurveKey) {
		if (curve.keys.length <= 1)
			return;
		var before = hrt.prefab.Diff.deepCopy(curve.save());
		curve.keys.remove(k);
		selected = null;
		commit(before);
	}

	function changed() {
		root.editor.rebuildPrefab(owner);
		refresh();
	}

	/** Records the change of the curve since `before` as an undo step, when there is one (a click without a move has none) **/
	function commit(before: Dynamic) {
		changed();
		if (haxe.Json.stringify(before) != haxe.Json.stringify(curve.save()))
			root.editor.recordPrefabUndo(curve, before, owner);
	}
}

#end
