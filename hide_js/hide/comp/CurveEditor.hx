package hide.comp;

#if (domkit && js)

import hrt.impl.Curve.CurveKeyMode;
import hide.kit.Curve;

typedef DisplayRange = {
	from : Float,
	to : Float
};

@:access(hide.kit.Element)
class CurveEditor extends SVG {
	public var svg(default, null) : js.html.svg.SVGElement;

	static inline var SAMPLES = 64;
	static inline var KEY_SIZE = 6;
	static inline var HANDLE_SIZE = 3;
	static inline var MAX_LINES = 6;
	static inline var BOX_MARGIN = 8;
	static inline var BOX_EDGE = 4;

	public var editor(default, null) : Curve;
	public var track(default, null) : CurveTrack;
	var large : Bool;
	var editable : Bool;
	var minX = 0.;
	var maxX = 1.;
	var minY = 0.;
	var maxY = 1.;
	var pad : Float;
	var selection : Array<hrt.impl.Curve.CurveKey> = [];
	var box : { x0: Float, y0: Float, x1: Float, y1: Float };
	var lastClick : { key: hrt.impl.Curve.CurveKey, time: Float };

	function single() return selection.length == 1 ? selection[0] : null;

	public function new(editor: Curve, large: Bool, activeTrack = 0) {
		super();
		svg = cast element[0];
		this.editor = editor;
		this.large = large;
		pad = large ? 4 : 2;
		setTrack(editor.tracks[activeTrack]);
		frame();
		if (!large)
			return;
		svg.addEventListener("wheel", onWheel);
		svg.addEventListener("pointerdown", onPointerDown);
		// no autoscroll of the middle button, that pans
		svg.addEventListener("mousedown", (e: js.html.MouseEvent) -> if (e.button == 1) e.preventDefault());
		svg.addEventListener("pointermove", (e: js.html.PointerEvent) -> {
			if (e.buttons != 0 || !editable)
				return;
			var m = mapping();
			var p = m.local(e);
			var part = keyAt(p.x, p.y, m.w, m.h) == null ? boxPartAt(p.x, p.y, m.w, m.h) : null;
			svg.style.cursor = if (part != null)
				switch ([part.dx, part.dy]) {
					case [0, 0]: "move";
					case [0, _]: "ns-resize";
					case [_, 0]: "ew-resize";
					case [dx, dy]: dx == dy ? "nwse-resize" : "nesw-resize";
				}
			else bandEdgeAt(p.x, p.y) != null ? "ns-resize" : "";
		});
		svg.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
			e.preventDefault();
			e.stopPropagation();
			if (editable)
				onContextMenu(e);
		});
	}

	public function setTrack(t: CurveTrack) {
		if (t == track)
			return;
		track = t;
		editable = large && track.curve != null;
		selection = [];
		onTrackChange();
	}

	public dynamic function onTrackChange() {}

	public static function thumbnail(curve: hrt.impl.Curve) : js.html.svg.SVGElement {
		var svg = new SVG();
		svg.element.attr({ viewBox: "0 0 1 1", preserveAspectRatio: "none" });
		svg.polygon(svg.element, [for (i in 0...SAMPLES + 1) new h2d.col.Point(i / SAMPLES, 1 - curve.getVal(i / SAMPLES))]).addClass("main").attr("vector-effect", "non-scaling-stroke");
		return cast svg.element[0];
	}

	static function displayRanges(t: CurveTrack) : Array<DisplayRange> {
		var rs : Array<DisplayRange> = [for (r in t.ranges) { from: r.from.v(), to: r.to.v() }];
		return switch (rs.length) {
			case 0: [{ from: 0, to: 1 }];
			case 2: [{ from: (rs[0].from + rs[1].from) * 0.5, to: (rs[0].to + rs[1].to) * 0.5 }].concat(rs);
			default: rs;
		}
	}

	static function lines(t: CurveTrack) : Array<{ f: Float -> Float, r: DisplayRange, main: Bool }> {
		if (t.curve == null)
			return [];
		return [for (i => r in displayRanges(t)) { f: t.curve.getVal, r: r, main: i == 0 }];
	}

	static inline function near(x: Float, y: Float, px: Float, py: Float, d: Float) return Math.abs(px - x) <= d && Math.abs(py - y) <= d;

	static function handles(k: hrt.impl.Curve.CurveKey) : Array<{ h: hrt.impl.Curve.CurveHandle, next: Bool }> {
		if (k.mode == CurveKeyMode.Linear || k.mode == CurveKeyMode.Constant)
			return [];
		return [for (next in [false, true]) {
			var h = next ? k.nextHandle : k.prevHandle;
			if (h != null) { h: h, next: next };
		}];
	}

	public function keepView(other: CurveEditor) {
		minX = other.minX;
		maxX = other.maxX;
		minY = other.minY;
		maxY = other.maxY;
	}

	public function frame() {
		minX = 0;
		var end = editor.maxTime;
		if (!Math.isFinite(end)) {
			end = 1.;
			for (t in editor.tracks)
				if (t.curve != null && t.curve.keys.length > 0)
					end = Math.max(end, t.curve.keys[t.curve.keys.length - 1].time);
		}
		maxX = end;
		minY = 0;
		maxY = 1;
		for (t in editor.tracks)
			for (l in lines(t))
				for (i in 0...SAMPLES + 1) {
					var y = hxd.Math.lerp(l.r.from, l.r.to, l.f(i / SAMPLES * end));
					minY = Math.min(minY, y);
					maxY = Math.max(maxY, y);
				}
	}

	function onWheel(e: js.html.WheelEvent) {
		e.preventDefault();
		e.stopPropagation();
		var factor = e.deltaY + e.deltaX < 0 ? 1 / 1.125 : 1.125;
		var m = mapping();
		var p = m.local(e);
		var t = m.time(p.x), v = m.display(p.y);
		if (!e.altKey) {
			minX = t + (minX - t) * factor;
			maxX = t + (maxX - t) * factor;
		}
		if (!e.ctrlKey) {
			minY = v + (minY - v) * factor;
			maxY = v + (maxY - v) * factor;
		}
		refresh();
	}

	function pan(e: js.html.PointerEvent) {
		var m = mapping();
		var start = m.local(e), startX = [minX, maxX], startY = [minY, maxY];
		drag(e, (e) -> {
			var p = m.local(e);
			var dt = (p.x - start.x) / (m.w - pad * 2) * (startX[1] - startX[0]);
			var dv = (p.y - start.y) / (m.h - pad * 2) * (startY[1] - startY[0]);
			minX = startX[0] - dt;
			maxX = startX[1] - dt;
			minY = startY[0] + dv;
			maxY = startY[1] + dv;
			refresh();
		}, () -> {});
	}

	inline function toDisplay(v: Float) return trackDisplay(track, v);
	static function trackDisplay(t: CurveTrack, v: Float) {
		var r = displayRanges(t)[0];
		return hxd.Math.lerp(r.from, r.to, v);
	}
	inline function sx(t: Float, w: Float) return pad + (t - minX) / (maxX - minX) * (w - pad * 2);
	inline function sy(v: Float, h: Float) return h - pad - (v - minY) / (maxY - minY) * (h - pad * 2);

	static function gridStep(size: Float) {
		var i = Math.floor(Math.log(size / MAX_LINES) / Math.log(10)) * 3;
		var step = 0.;
		do {
			step = [1, 2, 5][((i % 3) + 3) % 3] * Math.pow(10, Math.floor(i++ / 3));
		} while (size / step > MAX_LINES);
		return step;
	}

	/** `v` without the float noise of the grid steps (0.30000000000000004) **/
	static function gridLabel(v: Float) return Std.string(Math.round(v * 1e6) / 1e6);

	public function refresh() {
		var w = svg.clientWidth, h = svg.clientHeight;
		if (w <= 0 || h <= 0)
			return;
		// the preview shows the whole curve, as edited from any window; the window keeps its view while editing
		if (!large)
			frame();
		clear();
		var g = element;
		function px(t: Float) return sx(t, w);
		function py(v: Float) return sy(v, h);
		if (large) {
			rectBetween(g, 0, 0, hxd.Math.clamp(px(0), 0, w), h).addClass("outside");
			rectBetween(g, hxd.Math.clamp(px(editor.maxTime), 0, w), 0, w, h).addClass("outside");
			var step = gridStep(maxY - minY);
			for (i in Math.ceil(minY / step)...Math.floor(maxY / step) + 1) {
				var y = py(i * step);
				line(g, 0, y, w, y).addClass(i == 0 ? "zero" : "grid");
				text(g, 2, y - 2 < 9 ? y + 9 : y - 2, gridLabel(i * step));
			}
			var step = gridStep(maxX - minX);
			for (i in Math.ceil(minX / step)...Math.floor(maxX / step) + 1) {
				var x = px(i * step);
				line(g, x, 0, x, h).addClass(i == 0 ? "zero" : "grid");
				text(g, x + 2, h - 3, gridLabel(i * step));
			}
		} else
			line(g, 0, py(0), w, py(0)).addClass("zero");

		var t0 = Math.max(minX, 0), t1 = Math.min(maxX, editor.maxTime);
		function points(f: Float -> Float, r: DisplayRange) {
			return [for (i in 0...SAMPLES + 1) { var t = hxd.Math.lerp(t0, t1, i / SAMPLES); new h2d.col.Point(px(t), py(hxd.Math.lerp(r.from, r.to, f(t)))); }];
		}
		function band(f0: Float -> Float, r0: DisplayRange, f1: Float -> Float, r1: DisplayRange) {
			var back = points(f1, r1);
			back.reverse();
			polygon2(g, points(f0, r0).concat(back)).addClass("band");
		}
		if (t1 > t0) {
			// the two curves of a curve range, the min and the max of a random curve
			var a = editor.tracks[0].curve, b = editor.tracks[1]?.curve;
			if (a != null && b != null)
				band(a.getVal, displayRanges(editor.tracks[0])[0], b.getVal, displayRanges(editor.tracks[1])[0]);
			for (t in editor.tracks) {
				var rs = displayRanges(t);
				if (t.curve != null && rs.length == 3)
					band(t.curve.getVal, rs[1], t.curve.getVal, rs[2]);
				for (l in lines(t))
					polygon(g, points(l.f, l.r)).addClass(l.main ? "main" : "extreme").toggleClass("other", large && t != track);
			}
		}

		function key(t: CurveTrack, k: hrt.impl.Curve.CurveKey) return square(g, px(k.time), py(trackDisplay(t, k.value)), KEY_SIZE).addClass("key");
		if (large)
			for (t in editor.tracks)
				if (t != track && t.curve != null)
					for (k in t.curve.keys)
						key(t, k).addClass("other");
		if (!editable)
			return;
		selection = selection.filter(k -> track.curve.keys.contains(k));
		var b = box == null ? selectionBox(w, h) : null;
		if (b != null)
			rectBetween(g, b.x0, b.y0, b.x1, b.y1).addClass("selection-box");
		var k = single();
		if (k != null)
			for (hd in handles(k)) {
				var x = px(k.time + hd.h.dt), y = py(toDisplay(k.value + hd.h.dv));
				line(g, px(k.time), py(toDisplay(k.value)), x, y).addClass("tangent");
				circle(g, x, y, HANDLE_SIZE).addClass("handle");
			}
		for (k in track.curve.keys)
			key(track, k).toggleClass("selected", selection.contains(k));
		if (box != null)
			rectBetween(g, box.x0, box.y0, box.x1, box.y1).addClass("keys-box");
	}

	function mapping() {
		var rect = svg.getBoundingClientRect();
		var w = rect.width, h = rect.height;
		var r = displayRanges(track)[0];
		var scale = r.to - r.from;
		var display =(y: Float) -> minY + (h - pad - y) / (h - pad * 2) * (maxY - minY);
		return {
			rect: rect,
			w: w,
			h: h,
			/** Keys can only move in time when the range is empty **/
			flat: Math.abs(scale) <= 1e-9,
			local: (e: js.html.MouseEvent) -> { x: e.clientX - rect.left, y: e.clientY - rect.top },
			time: (x: Float) -> minX + (x - pad) / (w - pad * 2) * (maxX - minX),
			display: display,
			value: (y: Float) -> (display(y) - r.from) / scale,
		};
	}

	function keyAt(x: Float, y: Float, w: Float, h: Float, ?t: CurveTrack) {
		t ??= track;
		return Lambda.find(t.curve.keys, k -> near(x, y, sx(k.time, w), sy(trackDisplay(t, k.value), h), KEY_SIZE));
	}

	function otherTrackAt(x: Float, y: Float, w: Float, h: Float) {
		return Lambda.find(editor.tracks, t -> t != track && t.curve != null && keyAt(x, y, w, h, t) != null);
	}

	function handleAt(x: Float, y: Float, w: Float, h: Float) {
		var k = single();
		if (k == null)
			return null;
		return Lambda.find(handles(k), hd -> near(x, y, sx(k.time + hd.h.dt, w), sy(toDisplay(k.value + hd.h.dv), h), HANDLE_SIZE + 2));
	}

	function selectionBox(w: Float, h: Float) {
		if (selection.length < 2)
			return null;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (k in selection) {
			var x = sx(k.time, w), y = sy(toDisplay(k.value), h);
			x0 = Math.min(x0, x);
			y0 = Math.min(y0, y);
			x1 = Math.max(x1, x);
			y1 = Math.max(y1, y);
		}
		return { x0: x0 - BOX_MARGIN, y0: y0 - BOX_MARGIN, x1: x1 + BOX_MARGIN, y1: y1 + BOX_MARGIN };
	}

	/**
		The part of the box of the selected keys at (x, y): its inside (0, 0), an edge (`dx`: -1 left, 1 right, `dy`: -1 top,
		1 bottom, 0 for the other axis) or a corner. Null out of it
	**/
	function boxPartAt(x: Float, y: Float, w: Float, h: Float) : { dx: Int, dy: Int } {
		var b = selectionBox(w, h);
		if (b == null || x < b.x0 - BOX_EDGE || x > b.x1 + BOX_EDGE || y < b.y0 - BOX_EDGE || y > b.y1 + BOX_EDGE)
			return null;
		inline function side(v: Float, v0: Float, v1: Float) return Math.abs(v - v0) <= BOX_EDGE ? -1 : Math.abs(v - v1) <= BOX_EDGE ? 1 : 0;
		return { dx: side(x, b.x0, b.x1), dy: side(y, b.y0, b.y1) };
	}

	public function onKeyDown(e: js.html.KeyboardEvent) {
		if (e.ctrlKey)
			return;
		switch (e.key) {
			case "f":
				frame();
				refresh();
			case "Delete" if (editable && selection.length > 0):
				track.deleteKeys(selection);
			default:
				return;
		}
		e.preventDefault();
		e.stopPropagation();
	}

	function onPointerDown(e: js.html.PointerEvent) {
		e.preventDefault();
		e.stopPropagation();
		(cast svg.closest("kit-curve-view") : js.html.Element).focus();
		if (e.button == 1) {
			pan(e);
			return;
		}
		if (!large || editor.isDisabled() || e.button != 0)
			return;
		var m = mapping();
		var p = m.local(e);
		var other = (editable ? keyAt(p.x, p.y, m.w, m.h) : null) == null ? otherTrackAt(p.x, p.y, m.w, m.h) : null;
		if (other != null) {
			setTrack(other);
			refresh();
			onPointerDown(e);
			return;
		}
		if (!editable)
			return;
		var curve = track.curve;

		var hd = handleAt(p.x, p.y, m.w, m.h);
		if (hd != null) {
			dragHandle(e, single(), hd.h, hd.next);
			return;
		}
		var key = keyAt(p.x, p.y, m.w, m.h);
		if (key == null) {
			// Ctrl + click in the box adds a key, on its edges scales the keys around their center
			var part = e.shiftKey ? null : boxPartAt(p.x, p.y, m.w, m.h);
			if (part != null && !(e.ctrlKey && part.dx == 0 && part.dy == 0)) {
				if (part.dx == 0 && part.dy == 0) {
					var first = selection[0];
					for (k in selection)
						if (k.time < first.time)
							first = k;
					moveKeys(e, first);
				} else
					scaleKeys(e, part);
				return;
			}
			var edge = e.ctrlKey || e.shiftKey ? null : bandEdgeAt(p.x, p.y);
			if (edge != null) {
				scaleBand(e, edge);
				return;
			}
			if (!e.ctrlKey) {
				selectBox(e, p, e.shiftKey);
				return;
			}
			var t = hxd.Math.clamp(m.time(p.x), 0, editor.maxTime);
			track.edit(() -> {
				key = curve.addKey(t, m.flat ? curve.getVal(t) : m.value(p.y), curve.keyMode);
				track.fixKey(key);
			}, true);
			selection = [key];
		} else {
			if (e.shiftKey) {
				if (!selection.remove(key))
					selection.push(key);
				refresh();
				return;
			}
			// the svg is redrawn by the first click: the double click is found here, not by a dblclick event
			var now = haxe.Timer.stamp();
			if (lastClick != null && lastClick.key == key && now - lastClick.time < 0.4) {
				lastClick = null;
				editKey(key, e.clientX, e.clientY);
				return;
			}
			lastClick = { key: key, time: now };
			if (!selection.contains(key))
				selection = [key];
			refresh();
		}
		moveKeys(e, key);
	}

	function selectBox(e: js.html.PointerEvent, start: { x: Float, y: Float }, add: Bool) {
		var m = mapping();
		var initial = add ? selection.copy() : [];
		box = { x0: start.x, y0: start.y, x1: start.x, y1: start.y };
		selection = initial.copy();
		refresh();
		drag(e, (e) -> {
			var p = m.local(e);
			box.x1 = p.x;
			box.y1 = p.y;
			var x0 = Math.min(box.x0, box.x1), x1 = Math.max(box.x0, box.x1), y0 = Math.min(box.y0, box.y1), y1 = Math.max(box.y0, box.y1);
			selection = initial.copy();
			for (k in track.curve.keys) {
				var x = sx(k.time, m.w), y = sy(toDisplay(k.value), m.h);
				if (x >= x0 && x <= x1 && y >= y0 && y <= y1 && !selection.contains(k))
					selection.push(k);
			}
			refresh();
		}, () -> {
			box = null;
			refresh();
		});
	}

	function bandEdgeAt(x: Float, y: Float) : Null<Int> {
		if (track.ranges.length != 2)
			return null;
		var m = mapping();
		var t = m.time(x);
		if (t < 0 || t > editor.maxTime)
			return null;
		var c = track.curve.getVal(t);
		var rs = displayRanges(track);
		for (edge in [1, -1]) {
			var r = rs[edge == 1 ? 2 : 1];
			if (Math.abs(sy(hxd.Math.lerp(r.from, r.to, c), m.h) - y) <= KEY_SIZE)
				return edge;
		}
		return null;
	}

	/**
		Drags the `edge` of the band of a random curve (1: its max, -1: its min) up and down: grabbed in the first half
		of the time, the band widens or narrows around the middle of its `from` bounds, in the second half around the
		middle of its `to` ones, the edge following the mouse (the half width of the band is `lerp(from, to, curve)`).
		An undo step
	**/
	function scaleBand(e: js.html.PointerEvent, edge: Int) {
		var m = mapping();
		var t = m.time(m.local(e).x);
		var c = track.curve.getVal(t);
		var birth = t < 0.5;
		var bounds = [for (r in track.ranges) birth ? r.from : r.to];
		var other = [for (r in track.ranges) birth ? r.to : r.from];
		var center = (bounds[0].v() + bounds[1].v()) * 0.5, otherCenter = (other[0].v() + other[1].v()) * 0.5;
		var otherHalf = (other[1].v() - other[0].v()) * 0.5;
		var weight = birth ? 1 - c : c;
		var mid = birth ? hxd.Math.lerp(center, otherCenter, c) : hxd.Math.lerp(otherCenter, center, c);
		if (Math.abs(weight) < 1e-3)
			return;
		drag(e, (e) -> {
			var half = Math.max(edge * (m.display(m.local(e).y) - mid), 0);
			var h = Math.max((half - (1 - weight) * otherHalf) / weight, 0);
			inline function round(v: Float) return Math.round(v * 1000) / 1000;
			track.edit(() -> {
				bounds[0].set(round(center - h));
				bounds[1].set(round(center + h));
			}, true);
		}, () -> track.edit(null, false));
	}

	/**
		The bounds that `k` moves, alone, in a random curve (its middle, its min, its max): the `from` ones for its
		first key at 0, the `to` ones for its last key at 1. The band keeps there the width of its bounds, that the
		value of the key would change (the band is `lerp(from, to, key)` wide)
	**/
	function endBounds(k: hrt.impl.Curve.CurveKey) : Array<TrackBound> {
		var keys = track.curve.keys;
		if (track.ranges.length != 2 || selection.length != 1)
			return null;
		if (k == keys[0] && k.value == 0)
			return [for (r in track.ranges) r.from];
		if (k == keys[keys.length - 1] && k.value == 1)
			return [for (r in track.ranges) r.to];
		return null;
	}

	function moveBounds(e: js.html.PointerEvent, bounds: Array<TrackBound>) {
		var m = mapping();
		var start = [for (b in bounds) b.v()];
		var startValue = (start[0] + start[1]) * 0.5;
		drag(e, (e) -> {
			var v = m.display(m.local(e).y);
			v = e.ctrlKey ? Math.round(v * 10) / 10 : v;
			var shift = e.altKey ? 0 : Math.round((v - startValue) * 1000) / 1000;
			track.edit(() -> for (j => b in bounds) b.set(start[j] + shift), true);
		}, () -> track.edit(null, false));
	}

	function moveKeys(e: js.html.PointerEvent, grabbed: hrt.impl.Curve.CurveKey) {
		var bounds = endBounds(grabbed);
		if (bounds != null) {
			moveBounds(e, bounds);
			return;
		}
		var m = mapping();
		var curve = track.curve;
		var r = displayRanges(track)[0];
		var keys = selection.copy();
		var start = [for (k in keys) { time: k.time, value: k.value }];
		var grabbedStart = start[keys.indexOf(grabbed)];
		var minDt = Math.NEGATIVE_INFINITY, maxDt = Math.POSITIVE_INFINITY;
		for (j => k in keys) {
			var i = curve.keys.indexOf(k);
			var prev = curve.keys[i - 1], next = curve.keys[i + 1];
			if (prev == null || !keys.contains(prev))
				minDt = Math.max(minDt, (prev?.time ?? 0) - start[j].time);
			if (next == null || !keys.contains(next))
				maxDt = Math.min(maxDt, (next?.time ?? editor.maxTime) - start[j].time);
		}
		var p0 = m.local(e);
		var t0 = m.time(p0.x), v0 = m.flat ? 0 : m.value(p0.y);
		drag(e, (e) -> {
			var p = m.local(e);
			var t = grabbedStart.time + m.time(p.x) - t0, v = m.flat ? grabbedStart.value : grabbedStart.value + m.value(p.y) - v0;
			if (e.ctrlKey) {
				t = Math.round(t * 10) / 10;
				if (!m.flat)
					v = (Math.round(toDisplay(v) * 10) / 10 - r.from) / (r.to - r.from);
			}
			var dt = e.shiftKey ? 0 : hxd.Math.clamp(t - grabbedStart.time, minDt, maxDt);
			var dv = e.altKey ? 0 : v - grabbedStart.value;
			track.edit(() -> for (j => k in keys) {
				k.time = start[j].time + dt;
				k.value = start[j].value + dv;
			}, true);
		}, () -> track.edit(null, false));
	}

	function scaleKeys(e: js.html.PointerEvent, part: { dx: Int, dy: Int }) {
		var m = mapping();
		var curve = track.curve;
		var keys = selection.copy();
		var start = [for (k in keys) {
			time: k.time,
			value: k.value,
			handles: [for (h in [k.prevHandle, k.nextHandle]) if (h != null) { h: h, dt: h.dt, dv: h.dv }],
		}];
		var tMin = Math.POSITIVE_INFINITY, tMax = Math.NEGATIVE_INFINITY, vMin = Math.POSITIVE_INFINITY, vMax = Math.NEGATIVE_INFINITY;
		for (s in start) {
			tMin = Math.min(tMin, s.time);
			tMax = Math.max(tMax, s.time);
			vMin = Math.min(vMin, s.value);
			vMax = Math.max(vMax, s.value);
		}
		var scaleTime = part.dx != 0 && tMax - tMin > 1e-9;
		var edgeT = part.dx < 0 ? tMin : tMax, anchorT = part.dx < 0 ? tMax : tMin;
		var scaleValue = part.dy != 0 && !m.flat && vMax - vMin > 1e-9;
		var maxOnTop = sy(toDisplay(vMax), m.h) < sy(toDisplay(vMin), m.h);
		var edgeV = (part.dy < 0) == maxOnTop ? vMax : vMin, anchorV = edgeV == vMax ? vMin : vMax;
		if (!scaleTime && !scaleValue)
			return;

		function timeLimits(anchor: Float) {
			var sMin = 0., sMax = Math.POSITIVE_INFINITY;
			for (j => k in keys) {
				var i = curve.keys.indexOf(k);
				var prev = curve.keys[i - 1], next = curve.keys[i + 1];
				var lo = prev == null ? 0 : keys.contains(prev) ? Math.NEGATIVE_INFINITY : prev.time;
				var hi = next == null ? editor.maxTime : keys.contains(next) ? Math.POSITIVE_INFINITY : next.time;
				var d = start[j].time - anchor;
				if (d > 1e-9) {
					sMin = Math.max(sMin, (lo - anchor) / d);
					sMax = Math.min(sMax, (hi - anchor) / d);
				} else if (d < -1e-9) {
					sMin = Math.max(sMin, (hi - anchor) / d);
					sMax = Math.min(sMax, (lo - anchor) / d);
				}
			}
			return { min: sMin, max: sMax };
		}
		var centerT = (tMin + tMax) * 0.5, centerV = (vMin + vMax) * 0.5;
		var limits = timeLimits(anchorT), centerLimits = timeLimits(centerT);

		var p0 = m.local(e);
		var t0 = m.time(p0.x), v0 = m.flat ? 0 : m.value(p0.y);
		drag(e, (e) -> {
			var p = m.local(e);
			var at = e.ctrlKey ? centerT : anchorT, av = e.ctrlKey ? centerV : anchorV;
			var l = e.ctrlKey ? centerLimits : limits;
			var st = scaleTime ? hxd.Math.clamp((edgeT + m.time(p.x) - t0 - at) / (edgeT - at), l.min, l.max) : 1.;
			var sv = scaleValue ? Math.max((edgeV + m.value(p.y) - v0 - av) / (edgeV - av), 0) : 1.;
			track.edit(() -> for (j => k in keys) {
				var s = start[j];
				if (scaleTime)
					k.time = at + (s.time - at) * st;
				if (scaleValue)
					k.value = av + (s.value - av) * sv;
				for (hs in s.handles) {
					hs.h.dt = hs.dt * st;
					hs.h.dv = hs.dv * sv;
				}
			}, true);
		}, () -> track.edit(null, false));
	}

	function onContextMenu(e: js.html.MouseEvent) {
		if (editor.isDisabled())
			return;
		var curve = track.curve;
		var m = mapping();
		var p = m.local(e);
		var key = keyAt(p.x, p.y, m.w, m.h);
		if (key != null) {
			if (!selection.contains(key))
				selection = [key];
			refresh();
			keyMenu(e, key);
			return;
		}
		menu(e, [{ label: "Add key", keys: "Ctrl + click", click: () -> {
			var t = hxd.Math.clamp(m.time(p.x), 0, editor.maxTime);
			track.edit(() -> {
				var k = curve.addKey(t, m.flat ? curve.getVal(t) : m.value(p.y), curve.keyMode);
				track.fixKey(k);
				selection = [k];
			}, false);
		} }]);
	}

	/** Drags `handle` of `k`, the other one following it in the Aligned mode, opposite and of the same length on screen **/
	function dragHandle(e: js.html.PointerEvent, k: hrt.impl.Curve.CurveKey, handle: hrt.impl.Curve.CurveHandle, next: Bool) {
		var m = mapping();
		var other = next ? k.prevHandle : k.nextHandle;
		inline function kx() return sx(k.time, m.w);
		inline function ky() return sy(toDisplay(k.value), m.h);
		var otherLength = other == null ? 0. : hxd.Math.distance(sx(k.time + other.dt, m.w) - kx(), sy(toDisplay(k.value + other.dv), m.h) - ky());
		drag(e, (e) -> {
			var p = m.local(e);
			var x = next ? Math.max(p.x, kx()) : Math.min(p.x, kx());
			track.edit(() -> {
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
			}, true);
		}, () -> track.edit(null, false));
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

	function keyMenu(e: js.html.MouseEvent, k: hrt.impl.Curve.CurveKey) {
		var curve = track.curve;
		var keys = selection.copy();
		var items : Array<hrt.ui.HuiMenu.MenuItem> = [for (mode in [CurveKeyMode.Aligned, CurveKeyMode.Free, CurveKeyMode.Linear, CurveKeyMode.Constant]) {
			label: Std.string(["Aligned", "Free", "Linear", "Constant"][(cast mode : Int)]),
			radio: () -> Lambda.foreach(keys, k -> k.mode == mode),
			click: () -> track.edit(() -> {
				for (k in keys) {
					k.mode = mode;
					track.fixKey(k);
				}
				curve.keyMode = mode;
			}, false),
		}];
		items.push({ isSeparator: true });
		items.push({ label: "Edit time and value", click: () -> editKey(k, e.clientX, e.clientY), enabled: keys.length == 1 });
		items.push({ label: keys.length == 1 ? "Delete key" : "Delete keys", keys: "Delete", click: () -> track.deleteKeys(keys), enabled: curve.keys.length > keys.length });
		menu(e, items);
	}

	/**
		A context menu at the mouse in the document of the svg (the curve window), from the svg: the target of the event
		(a key, the curve) is replaced when the svg is redrawn, and a menu closes once its element leaves the page
	**/
	function menu(e: js.html.MouseEvent, items: Array<hrt.ui.HuiMenu.MenuItem>) {
		new hide.comp.ContextMenu(items, cast svg, null, { x: e.clientX, y: e.clientY });
	}

	function editKey(k: hrt.impl.Curve.CurveKey, x: Float, y: Float) {
		var curve = track.curve;
		var parent = svg.parentElement;
		var popup = new hide.comp.Popup(new hide.Element(parent), false);
		var content = new hide.Element('<div class="keyPopup">
			<div class="line"><label>Time</label><input class="t" type="number" step="0.05"/></div>
			<div class="line"><label>Value</label><input class="v" type="number" step="0.1"/></div>
		</div>').appendTo(popup.element);
		var rect = parent.getBoundingClientRect();
		popup.position = Inside;
		popup.offsetX = x + 8 - rect.left;
		popup.offsetY = y - 20 - rect.top;
		popup.onClose = () -> popup.element.remove();
		var r = displayRanges(track)[0];
		var t = content.find(".t"), v = content.find(".v");
		t.val(hxd.Math.fmt(k.time));
		v.val(hxd.Math.fmt(toDisplay(k.value)));
		v.prop("disabled", mapping().flat);
		function set(f: Float -> Void, input: hide.Element) {
			var f2 = Std.parseFloat(input.val());
			if (Math.isNaN(f2))
				return;
			track.edit(() -> f(f2), false);
		}
		t.change((_) -> set(f -> {
			var i = curve.keys.indexOf(k);
			k.time = hxd.Math.clamp(f, curve.keys[i - 1]?.time ?? 0, curve.keys[i + 1]?.time ?? editor.maxTime);
		}, t));
		v.change((_) -> set(f -> k.value = (f - r.from) / (r.to - r.from), v));
		t.focus();
	}
}

#end
