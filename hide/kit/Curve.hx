package hide.kit;

#if domkit

import hrt.impl.Curve.CurveKeyMode;
#if js
import hide.comp.curveeditor.CurveEditor;

typedef CurveWindow = {
	var sub : hide.comp.SubWindow;
	var edited : Curve;
	var content : CurveEditor;
	var fields : KitRoot;
}
#end

typedef TrackBound = {
	v : () -> Float,
	set : Float -> Void
};

/** The random amount around a track (its band is the curve minus and plus it), `from` at time 0 and `to` at time 1 **/
typedef TrackSpread = {
	from : TrackBound,
	to : TrackBound
};

typedef CurveBand = {
	a : CurveTrack,
	b : CurveTrack
};

typedef CurvePreset = {
	name : String,
	keys : Array<{ t : Float, v : Float, ?slope : Float }>
};

@:access(hrt.prefab.Prefab)
@:access(hide.kit.KitRoot)
class Curve extends Element {
	public var maxTime = 1.;
	public var label : String;
	public var tracks : Array<CurveTrack> = [];
	public var bands : Array<CurveBand> = [];
	public var curvePath : String;
	public var curveChoices : Array<Select.SelectEntry>;

	public static var PRESETS : Array<CurvePreset> = [
		{ name: "Constant", keys: [{ t: 0, v: 1 }, { t: 1, v: 1 }] },
		{ name: "Linear", keys: [{ t: 0, v: 0 }, { t: 1, v: 1 }] },
		{ name: "Linear, decreasing", keys: [{ t: 0, v: 1 }, { t: 1, v: 0 }] },
		{ name: "Ease in", keys: [{ t: 0, v: 0, slope: 0 }, { t: 1, v: 1, slope: 2 }] },
		{ name: "Ease out", keys: [{ t: 0, v: 0, slope: 2 }, { t: 1, v: 1, slope: 0 }] },
		{ name: "Ease in out", keys: [{ t: 0, v: 0, slope: 0 }, { t: 1, v: 1, slope: 0 }] },
		{ name: "Bell", keys: [{ t: 0, v: 0, slope: 0 }, { t: 0.5, v: 1, slope: 0 }, { t: 1, v: 0, slope: 0 }] },
		{ name: "Fade in out", keys: [{ t: 0, v: 0 }, { t: 0.2, v: 1 }, { t: 0.8, v: 1 }, { t: 1, v: 0 }] },
	];

	#if js
	static inline var WINDOW_BOUNDS_KEY = "curveEditorWindow";
	static var win : CurveWindow;

	var preview : hide.comp.curveeditor.CurveThumbnail;
	#end

	public function new(parent: Element, id: String, label: String) {
		super(parent, id);
		this.label = label;
	}

	public function refresh() {
		#if js
		preview?.refresh();
		if (win?.edited == this) {
			win.content.refresh();
			win.fields.refreshFields();
		}
		#end
	}

	public function addTrack(curve: hrt.impl.Curve, ?spread: TrackSpread) : CurveTrack {
		var t = new CurveTrack(curve, spread, this);
		tracks.push(t);
		return t;
	}

	public function addBand(a: CurveTrack, b: CurveTrack) {
		bands.push({ a: a, b: b });
	}

	public static function getCurveFromPreset(p: CurvePreset) : hrt.impl.Curve {
		var c = new hrt.impl.Curve();
		for (i => k in p.keys) {
			var key = c.addKey(k.t, k.v, k.slope == null ? CurveKeyMode.Linear : CurveKeyMode.Aligned);
			if (k.slope != null) {
				var prev = (k.t - (p.keys[i - 1]?.t ?? k.t - 0.3)) / 3, next = ((p.keys[i + 1]?.t ?? k.t + 0.3) - k.t) / 3;
				key.prevHandle = new hrt.impl.Curve.CurveHandle(-prev, -prev * k.slope);
				key.nextHandle = new hrt.impl.Curve.CurveHandle(next, next * k.slope);
			}
		}
		return c;
	}

	override function canCopy() {
		return true;
	}

	override function canPaste() {
		return true;
	}

	override function copySelf(target: Dynamic) {
		target.tracks = [for (t in tracks) { curve: t.data == null ? null : @:privateAccess t.data.copyToDynamic(null), spread: t.spread == null ? null : [t.spread.from.v(), t.spread.to.v()] }];
	}

	override function pasteSelf(data: Dynamic) {
		var copied : Array<{ curve: Dynamic, spread: Array<Float> }> = data.tracks;
		if (copied == null)
			return;
		root.editor.beginMultiUndo();
		for (i => t in tracks) {
			var c = copied[i];
			if (c == null)
				continue;
			t.edit(() -> {
				if (c.curve != null && t.data != null) {
					var keys = new hrt.impl.Curve();
					@:privateAccess keys.copyFromDynamic(hrt.prefab.Diff.deepCopy(c.curve));
					t.data.keys = keys.keys;
				}
				if (c.spread != null && t.spread != null) {
					t.spread.from.set(c.spread[0]);
					t.spread.to.set(c.spread[1]);
				}
			}, false);
		}
		root.editor.finishMultiUndo();
	}

	override function makeSelf() {
		#if js
		var e = js.Browser.document.createElement("kit-curve-editor");
		preview = new hide.comp.curveeditor.CurveThumbnail(tracks, bands, maxTime);
		e.appendChild(preview.svg);
		e.title = "Edit the curve";
		e.addEventListener("click", (_) -> if (!isDisabled()) openWindow());
		setupPropLine(null, cast e, false);
		if (win != null && sameAs(win.edited))
			bindWindow();
		#else
		super.makeSelf();
		#end
	}

	#if js
	function sameAs(other: Curve) {
		return other.root.prefab == root.prefab && other.getIdPath() == getIdPath();
	}

	function openWindow() {
		if (win == null)
			createWindow();
		bindWindow();
		win.sub.focus();
	}

	function bindWindow() {
		var previous = win.edited != null && sameAs(win.edited) ? win.content : null;
		win.edited = this;
		win.sub.anchor = native.get();
		win.sub.title = label;
		var content = js.Browser.document.createElement("kit-curve-editor-window");
		win.sub.setContent(content);

		var body = js.Browser.document.createElement("kit-curve-body");
		content.appendChild(body);

		// the widgets of the window edit the prefab of the inspector, apart from its tree
		var fields = new KitRoot(null, null, root.prefab, root.editor);
		fields.header = false;
		fields.classList.push("kit-curve-fields-root");
		win.fields = fields;
		var view : CurveEditor = null;
		var reference : Line = null;
		if (curveChoices != null) {
			reference = new Line(fields, "reference");
			reference.full = true;
			reference.classList.push("kit-curve-reference");
			new Text(reference, "curveLabel", "Reference");
			var select = new Select(reference, "curve", curveChoices);
			select.value = curvePath;
			select.onValueChange = (_) -> onCurveChange(select.value);
		}
		var rows = [];
		for (i => t in tracks) {
			var line = new Line(fields, "track" + i);
			line.full = true;
			line.classList.push("kit-curve-fields");
			if (tracks.length > 1)
				line.classList.push("kit-curve-selectable");
			rows.push(line);
			if (t.name != null)
				new Text(line, "name", t.name);
			if (t.data != null)
				for (f in [{ id: "flipTime", text: "↔", tooltip: "Flip the curve in time", flip: t.flipTime }, { id: "flipValue", text: "↕", tooltip: "Flip the curve in value", flip: t.flipValue }]) {
					var button = new Button(line, f.id, f.text);
					button.tooltip = f.tooltip;
					// the flips record their own undo step
					button.noUndo = true;
					button.onClick = f.flip;
				}
			new Spacer(line, "push");
			if (t.spread != null)
				for (side in ["From", "To"]) {
					// the absolute bounds of the band at the start / end: one moves, the other stays and the curve is recentered between them (`moveEdge`)
					var time = side == "From" ? 0. : 1.;
					for (j => edge in [-1, 1]) {
						var s = new Slider<Float>(line, side + j);
						s.label = j == 0 ? side : "";
						s.tooltip = side + (j == 0 ? " min" : " max");
						s.decimals = 3;
						// the edit records its own undo step, with the keys of the curve
						s.noUndo = true;
						function bound() return t.edgeAt(time, edge);
						s.value = bound();
						@:privateAccess s.getFieldValue = bound;
						s.onValueChange = (temp) -> t.edit(() -> t.moveEdge(time, edge, s.value), temp);
					}
				}
		}
		fields.make();
		body.appendChild(fields.native.get());
		reference?.native.get().style.setProperty("grid-row", "span " + tracks.length);

		for (i => row in rows) {
			if (tracks.length > 1) {
				row.native.get().addEventListener("pointerdown", (_) -> {
					view.setTrack(tracks[i]);
					view.refresh();
				});
			}
		}

		var area = js.Browser.document.createElement("kit-curve-view");
		area.tabIndex = 0;
		body.appendChild(area);
		var active = previous == null ? 0 : previous.editor.tracks.indexOf(previous.track);
		view = new CurveEditor(this, active < tracks.length ? active : 0);
		win.content = view;
		if (previous != null)
			view.keepView(previous);
		area.appendChild(view.svg);
		area.addEventListener("keydown", view.onKeyDown);

		var presets = js.Browser.document.createElement("kit-presets");
		content.appendChild(presets);
		function fillPresets() {
			presets.innerHTML = "";
			for (i => row in rows)
				row.native.toggleClass("active", tracks.length > 1 && tracks[i] == view.track);
			if (view.track.data == null) {
				var hint = js.Browser.document.createElement("kit-curve-hint");
				hint.innerText = "A missing curve, or not a plain one: it is not edited here";
				presets.appendChild(hint);
				return;
			}
			for (p in PRESETS) {
				var thumb = new hide.comp.curveeditor.CurveThumbnail([new CurveTrack(getCurveFromPreset(p), null, null)], [], 1).svg;
				thumb.addEventListener("click", (_) -> view.track.applyPreset(p));
				presets.appendChild(thumb);
			}
		}

		fillPresets();
		view.onTrackChange = fillPresets;
		win.sub.window.requestAnimationFrame((_) -> view.refresh());
		area.focus();
	}

	static function createWindow() {
		var sub = new hide.comp.SubWindow(640, 400, WINDOW_BOUNDS_KEY);
		win = { sub: sub, edited: null, content: null, fields: null };
		sub.onResize = () -> win.content.refresh();
		sub.onKeyDown = onWindowKeyDown;
		sub.onClose = () -> win = null;
	}

	static function onWindowKeyDown(e: js.html.KeyboardEvent) {
		var target : js.html.Element = cast e.target;
		if (!e.ctrlKey || target.tagName == "INPUT")
			return;
		var native = win.edited.native.get();
		var view = Lambda.find(@:privateAccess hide.Ide.inst.views, v -> v.element[0].contains(native));
		view?.processKeyEvent(new js.jquery.Event(cast e));
	}
	#end

	public dynamic function onValueChange(temporaryEdit: Bool) : Void {}

	public dynamic function onCurveChange(path: String) : Void {}
}

@:access(hrt.prefab.Prefab)
@:access(hide.kit.Element)
@:access(hrt.prefab.EditContext2)
class CurveTrack {
	public var editor(default, null) : Curve;

	public var name : String;
	public var data : hrt.impl.Curve;
	public var spread : TrackSpread;

	var editStart : Dynamic;

	public function new(data: hrt.impl.Curve, spread: TrackSpread, editor: Curve) {
		this.editor = editor;
		this.spread = spread;
		this.data = data;
	}

	public function edit(f: () -> Void, temp: Bool) {
		if (f == null && editStart == null)
			return;
		var before = editStart ??= keys();
		var after : Dynamic = null;
		function apply(isUndo: Bool) {
			if (after == null)
				after = keys();
			else if (data != null)
				@:privateAccess data.copyFromDynamic(hrt.prefab.Diff.deepCopy(isUndo ? before : after));
			rebuild();
		}

		var unchanged = f == null && haxe.Json.stringify(before) == haxe.Json.stringify(keys());
		editor.change({
			callback: () -> {
				if (f != null)
					f();
				editor.onValueChange(temp);
			},
			isTemporaryEdit: temp,
			recordUndo: true,
			sideEffects: unchanged ? null : apply,
		});
		if (!temp)
			editStart = null;
	}

	public function applyPreset(p: CurvePreset) {
		edit(() -> data.keys = Curve.getCurveFromPreset(p).keys, false);
	}

	/** The random amount around the curve at `time` **/
	public function spreadAt(time: Float) : Float {
		return spread == null ? 0. : hxd.Math.lerp(spread.from.v(), spread.to.v(), hxd.Math.clamp(time, 0, 1));
	}

	/** The value at `time` of the `edge` of the band (-1: min, 1: max, 0: the curve) **/
	public function edgeAt(time: Float, edge: Int) : Float {
		return (data?.getVal(time) ?? 0.) + edge * spreadAt(time);
	}

	/**
		Moves the `edge` of the band (-1: min, 1: max) at `time` to `value`, the other edge staying there: the amount of the
		nearest end (the start before 0.5) becomes the half width, and the curve is recentered between the edges by a shift
		of that end, linear in time down to 0 at the other end (that keeps the shape of the curve and its other end)
	**/
	public function moveEdge(time: Float, edge: Int, value: Float) {
		time = hxd.Math.clamp(time, 0, 1);
		var start = time < 0.5;
		var weight = start ? 1 - time : time;
		if (spread == null || weight < 1e-3)
			return;
		var other = edgeAt(time, -edge);
		var half = Math.max(edge * (value - other), 0) * 0.5;
		var bound = start ? spread.from : spread.to;
		bound.set(round(Math.max(bound.v() + (half - spreadAt(time)) / weight, 0)));
		if (data == null)
			return;
		var shift = (other + edge * spreadAt(time) - data.getVal(time)) / weight;
		var s0 = start ? shift : 0., s1 = start ? 0. : shift;
		for (k in data.keys) {
			k.value += hxd.Math.lerp(s0, s1, k.time);
			for (h in [k.prevHandle, k.nextHandle])
				if (h != null)
					h.dv += (s1 - s0) * h.dt;
		}
	}

	static inline function round(v: Float) return Math.round(v * 1e6) / 1e6;

	public function flipTime() {
		var end = Math.isFinite(editor.maxTime) ? editor.maxTime : data.keys[data.keys.length - 1].time;
		edit(() -> {
			for (k in data.keys) {
				k.time = end - k.time;
				var h = k.prevHandle;
				k.prevHandle = k.nextHandle;
				k.nextHandle = h;
				for (h in [k.prevHandle, k.nextHandle])
					if (h != null)
						h.dt = -h.dt;
			}
			data.keys.reverse();
			if (spread != null) {
				var v = spread.from.v();
				spread.from.set(spread.to.v());
				spread.to.set(v);
			}
		}, false);
	}

	public function flipValue() {
		edit(() -> {
			var min = Math.POSITIVE_INFINITY, max = Math.NEGATIVE_INFINITY;
			for (k in data.keys) {
				min = Math.min(min, k.value);
				max = Math.max(max, k.value);
			}
			for (k in data.keys) {
				k.value = min + max - k.value;
				for (h in [k.prevHandle, k.nextHandle])
					if (h != null)
						h.dv = -h.dv;
			}
		}, false);
	}

	public function fixKey(k: hrt.impl.Curve.CurveKey) {
		var i = data.keys.indexOf(k);
		var prev = data.keys[i - 1], next = data.keys[i + 1];
		switch (k.mode) {
			case Aligned, Free:
				k.prevHandle ??= new hrt.impl.Curve.CurveHandle(prev != null ? (prev.time - k.time) / 3 : -0.1, 0);
				k.nextHandle ??= new hrt.impl.Curve.CurveHandle(next != null ? (next.time - k.time) / 3 : 0.1, 0);
			case Linear, Constant:
				k.prevHandle = null;
				k.nextHandle = null;
		}
	}

	public function deleteKeys(keys: Array<hrt.impl.Curve.CurveKey>) {
		if (keys.length == 0 || data.keys.length - keys.length < 1)
			return;
		edit(() -> for (k in keys) data.keys.remove(k), false);
	}

	function keys() : Dynamic {
		return data == null ? null : @:privateAccess data.copyToDynamic(null);
	}

	function rebuild() {
		editor.root.editor.rebuildPrefab(@:privateAccess editor.root.prefab);
		function visit(e: Element) {
			var p = Std.downcast(e, Curve);
			if (p != null && Lambda.exists(p.tracks, t -> t.data == data))
				p.refresh();
			for (c in e.children)
				visit(c);
		}
		visit(editor.root);
	}
}

#end
