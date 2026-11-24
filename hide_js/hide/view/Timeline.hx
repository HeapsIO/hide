package hide.view;

import js.Browser.document;
import js.Browser.window;
import js.html.*;
import hrt.impl.Curve.CurveKey;
import hrt.impl.Curve.CurveHandle;
import hrt.impl.Curve.CurveKeyMode;

using Lambda;

enum Unit {
	Second;
	Frame;
}

enum ClearFlag {
	Full;
	Content;
}

typedef Row = {
	name : String,
	content : Element,
	?element : Element
}

typedef Marker = {
	name : String,
	frame : Int,
	?duration : Int,
	?element : Element
}

typedef TimelineCurve = {
	name : String,
	color : Int,
	getValue : Float -> Float,
	?data : hrt.impl.Curve,
	?dashed : Bool,
	?faded : Bool
}

private typedef CurvesEdit = {
	datas : Array<hrt.impl.Curve>,
	start : Array<Dynamic>
}

class Timeline extends hide.ui.View<{}> {
	static final MIN_STEP = 1e-2;
	static final MIN_ZOOM = 1e-4;
	static final MAX_ZOOM = 1e4;
	static final ZOOM_SPEED = 1.1;
	static final DRAG_THRESHOLD = 3;
	static final FRAME_ALL_PADDING = 20;
	static final LABEL_SPACING = 6;
	static final MAX_FRAME = 1 << 30;
	static final SPEEDS = [0.125, 0.25, 0.5, 1., 2., 4., 8.];
	static final HIT_DISTANCE = 6;
	static final PIXELS_PER_SAMPLE = 2;
	static final SVG_NS = "http://www.w3.org/2000/svg";

	public var unit(default, null) : Unit = Second;
	public var hasYAxis(default, null) : Bool = false;
	public var framerate(default, null) : Float = 60.;
	public var duration(default, null) : Float = 0.; // Seconds
	public var hasFilter(default, null) : Bool = false;
	public var filter(default, null) : String = "";
	public var isSeekable(default, set) : Bool = true;
	function set_isSeekable(v : Bool) {
		isSeekable = v;
		updateButtons();
		return v;
	}
	public var owner(default, set) : hide.ui.View<Dynamic>;
	function set_owner(v : hide.ui.View<Dynamic>) {
		owner = v;
		updateButtons();
		return v;
	}

	var needRedraw = true;
	var needFrameAll = false;

	var rows : Array<Row> = [];
	var markers : Array<Marker> = [];
	var curves : Array<TimelineCurve> = [];
	var selectedMarkers : Array<Marker> = [];
	var selectedKeys : Array<CurveKey> = [];

	var zoomX = 1.;
	var zoomY = 1.;
	var panX = 0.;
	var panY = 0.;
	var hstep = MIN_STEP;
	var vstep = MIN_STEP;
	var resizeObserver : hide.comp.ResizeObserver;
	var selectionBox : { x0 : Float, y0 : Float, x1 : Float, y1 : Float };

	var toolbar : Element;
	var leftPanel : Element;
	var rightPanel : Element;
	var grid : CanvasElement;
	var curvesSvg : Element;
	var content : Element;
	var playhead : Element;
	var time : SpanElement;
	var playButton : hide.html.comp.Button;
	var speedButton : hide.html.comp.Button;
	var seekButtons : Array<hide.html.comp.Button> = [];
	var filterInput : InputElement;
	var additionalWidgets : Array<Element> = [];

	// CSS Rules
	var rulerHeight = 0.;
	var keySize = 0.;
	var handleSize = 0.;
	var minHorizontalLabelSpacing = 0.;
	var minVerticalLabelSpacing = 0.;

	override function onDisplay() {
		var root = element.get(0);
		root.innerHTML = "";
		root.classList.add("timeline");

		hide.html.Html.build(root,
			<div class="timeline-root">
				<hide-toolbar id="toolbar">
					<hide-group>
						<hide-button id="start-button" title="Go to start" icon={HideRes.icon.fast_rewind} onclick={() -> setTime(0.)}/>
						<hide-button id="previous-button" title="Previous frame" icon={HideRes.icon.skip_previous} onclick={() -> setTime(Math.max(getTime() - frameToTime(1), 0.))}/>
						<hide-button id="play-button" title="Play / Pause" icon={HideRes.icon.play} onclick={() -> setPaused(!isPaused())}/>
						<hide-button id="next-button" title="Next frame" icon={HideRes.icon.skip_next} onclick={() -> setTime(Math.min(getTime() + frameToTime(1), duration))}/>
						<hide-button id="end-button" title="Go to end" icon={HideRes.icon.fast_forward} onclick={() -> setTime(duration)}/>
					</hide-group>
					<hide-button id="speed-button" title="Playback speed (click: faster, right click: slower)" onclick={() -> changeSpeed(1)} oncontextmenu={(e : MouseEvent) -> { e.preventDefault(); changeSpeed(-1); }}/>
					<hide-button title="Frame all (F)" icon={HideRes.icon.fullscreen} onclick={frameAll}/>
					<hide-button title="Settings" icon={HideRes.icon.settings} onclick={(e : MouseEvent) -> openSettings(cast e.currentTarget)}/>
					<hide-button title="Help" icon={HideRes.icon.question_mark} onclick={(e : MouseEvent) -> openHelp(cast e.currentTarget)}/>
				</hide-toolbar>
				<hide-split-container class="timeline-body">
					<div id="left-panel" class="left-panel" anchor="previous" size="250">
						<div class="filter">
							<span>Filter</span>
							<input id="filter-input" placeholder="property name" value={filter} oninput={() -> setFilter(filterInput.value)} onkeydown={onFilterKeyDown}/>
						</div>
					</div>
					<div id="right-panel" class="right-panel">
						<canvas id="grid"></canvas>
						<div id="content" class="content"></div>
						<div id="playhead" class="playhead">
							<span id="time" class="time"></span>
							<div class="line"></div>
						</div>
					</div>
				</hide-split-container>
			</div>
		);

		this.leftPanel = leftPanel;
		this.rightPanel = rightPanel;
		this.grid = grid;
		this.content = content;
		this.playhead = playhead;
		this.time = time;
		this.playButton = playButton;
		this.speedButton = speedButton;
		this.filterInput = filterInput;
		this.toolbar = toolbar;
		for (w in additionalWidgets)
			toolbar.append(w);
		seekButtons = [startButton, previousButton, nextButton, endButton];
		readStyle();
		updateButtons();

		curvesSvg = cast document.createElementNS(SVG_NS, "svg");
		curvesSvg.classList.add("curves");
		rightPanel.insertBefore(curvesSvg, content);

		for (r in rows)
			r.element = null;
		for (m in markers)
			m.element = null;

		leftPanel.classList.toggle("has-filter", hasFilter);
		rightPanel.onwheel = onWheel;
		rightPanel.onpointerdown = onRightPanelPointerDown;
		rightPanel.ondblclick = onRightPanelDoubleClick;
		rightPanel.oncontextmenu = (e : MouseEvent) -> e.preventDefault();

		keys.register("save", () -> onSave());
		keys.register("undo", () -> onUndo());
		keys.register("redo", () -> onRedo());
		keys.register("delete", deleteSelection);
		keys.register("selectAll", selectAll);
		keys.register("playPause", () -> setPaused(!isPaused()));
		keys.register("timeline.switchUnit", switchUnit);
		keys.register("sceneeditor.focus", frameAll);

		refresh();

		for (m in ide.getViews(Model)) {
			if (m.isActive())
				m.bindTimeline(this);
		}
		for (p in ide.getViews(Prefab)) {
			if (p.isActive())
				p.bindTimeline(this);
		}
		for (f in ide.getViews(FXEditor)) {
			if (f.isActive())
				f.bindTimeline(this);
		}

		resizeObserver?.disconnect();
		resizeObserver = new hide.comp.ResizeObserver((_, _) -> refresh());
		resizeObserver.observe(rightPanel);
	}

	override function getTitle() {
		return "Timeline";
	}

	override function destroy() {
		resizeObserver?.disconnect();
		resizeObserver = null;
		owner = null;
		super.destroy();
	}

	public function refresh() {
		needRedraw = true;
		if (owner == null)
			update();
	}

	public function update() {
		if (!isActive())
			return;

		var ratio = window.devicePixelRatio;
		if (grid.width != Math.round(rightPanel.clientWidth * ratio) || grid.height != Math.round(rightPanel.clientHeight * ratio))
			needRedraw = true;

		var t = getTime();
		var s = unitScale();
		var decimals = hxd.Math.imax(0, Math.ceil(-Math.log(hstep * s) / Math.log(10) - 1e-6));
		var f = Math.pow(10, decimals);
		time.textContent = '${Math.round(t * s * f) / f}';
		playhead.style.left = '${sx(t)}px';

		playButton.icon = Std.string(isPaused() ? HideRes.icon.play : HideRes.icon.pause);
		speedButton.label = 'x${getSpeed()}';

		if (needRedraw)
			redraw();
	}

	public function setUnit(u : Unit) {
		unit = u;
		refresh();
	}

	public function setHasYAxis(v : Bool) {
		hasYAxis = v;
		refresh();
	}

	public function setFramerate(v : Float) {
		framerate = v;
		refresh();
	}

	public function setHasFilter(v : Bool) {
		hasFilter = v;
		leftPanel?.classList.toggle("has-filter", v);
		refresh();
	}

	public function setFilter(v : String) {
		if (filterInput != null && filterInput.value != v)
			filterInput.value = v;
		if (v == filter)
			return;
		filter = v;
		onFilterChange(v);
	}

	public function setDuration(v : Float) {
		duration = v;
		refresh();
	}

	public function clear(flag : ClearFlag = Full) {
		for (r in rows)
			r.element?.remove();
		for (m in markers)
			m.element?.remove();
		for (w in additionalWidgets)
			w.remove();
		rows = [];
		additionalWidgets = [];
		markers = [];
		curves = [];
		selectedMarkers = [];

		if (flag == Full) {
			owner = null;
			isSeekable = true;
			hasYAxis = false;
			duration = 0.;
			setHasFilter(false);
			filter = "";
			if (filterInput != null)
				filterInput.value = "";
			onFilterChange = (_) -> {};
			selectedKeys = [];
			getTime = () -> 0.;
			setTime = (_) -> {};
			isPaused = () -> true;
			setPaused = (_) -> {};
			getSpeed = () -> 1.;
			setSpeed = (_) -> {};
			contextMenu = (_) -> [];
			onSave = () -> {};
			onDelete = (_) -> {};
			onChange = (_, _) -> {};
			onUndo = () -> {};
			onRedo = () -> {};
			onCurvesEdit = () -> {};
			onCurvesChange = (_, _, _) -> {};
		}

		refresh();
	}

	public function addToolbarWidgets(e : Element) {
		additionalWidgets.push(e);
		toolbar?.append(e);
	}

	public function addRow(name : String, content : Element) {
		var r : Row = { name: name, content: content };
		rows.push(r);
		refresh();
	}

	public function addMarker(name : String, frame : Int) {
		var m : Marker = { name: name, frame: frame };
		markers.push(m);
		refresh();
	}

	public function addCurve(c : TimelineCurve) {
		curves.push(c);
		refresh();
	}

	public function removeMarker(name : String, frame : Int) {
		var idx = markers.length - 1;
		while (idx >= 0) {
			var m = markers[idx];
			if (m.name == name && m.frame == frame) {
				markers.remove(m);
				m.element?.remove();
				selectedMarkers.remove(m);
				return;
			}
			idx--;
		}
	}

	public function frameAll() {
		needFrameAll = true;
		refresh();
	}

	public function selectMarkers(toSelect : Array<Marker>) {
		var sel = [];
		for (m in markers) {
			for (s in toSelect) {
				if (m.name == s.name && m.frame == s.frame && !sel.contains(m))
					sel.push(m);
			}
		}
		setSelection(sel, []);
	}

	public function selectKeys(toSelect : Array<CurveKey>) {
		setSelection([], toSelect.copy());
	}

	public dynamic function contextMenu(frame : Int) : Array<hrt.ui.HuiMenu.MenuItem> { return []; }
	public dynamic function getTime() : Float { return 0.; }
	public dynamic function setTime(t : Float) {}
	public dynamic function isPaused() : Bool { return true; }
	public dynamic function setPaused(v : Bool) {}
	public dynamic function getSpeed() : Float { return 1.; }
	public dynamic function setSpeed(v : Float) {}
	public dynamic function onSave() {}
	public dynamic function onDelete(markers : Array<Marker>) {}
	public dynamic function onChange(oldMarkers : Array<Marker>, newMarkers : Array<Marker>) {}
	public dynamic function onUndo() {}
	public dynamic function onRedo() {}
	public dynamic function onCurvesEdit() {}
	public dynamic function onCurvesChange(curves : Array<hrt.impl.Curve>, before : Array<Dynamic>, after : Array<Dynamic>) {}
	public dynamic function onFilterChange(filter : String) {}

	inline function frameToTime(f : Int) {
		return f / framerate;
	}

	inline function timeToFrame(t : Float) {
		return Math.round(t * framerate);
	}

	inline function unitScale() {
		return unit == Second ? 1. : framerate;
	}

	inline function gridWidth() {
		return rightPanel.clientWidth;
	}

	inline function gridHeight() {
		return rightPanel.clientHeight - rulerHeight;
	}

	inline function colorString(color : Int) {
		return "#" + StringTools.hex(color & 0xFFFFFF, 6);
	}


	inline function sx(px : Float) {
		return px * gridWidth() * zoomX + panX;
	}

	inline function sy(py : Float) {
		return gridHeight() - (py * gridHeight() * zoomY + panY);
	}

	inline function sxFromEvent(e : MouseEvent) {
		return e.clientX - rightPanel.getBoundingClientRect().left;
	}

	inline function syFromEvent(e : MouseEvent) {
		return e.clientY - rightPanel.getBoundingClientRect().top - rulerHeight;
	}

	inline function px(sx : Float) {
		return (sx - panX) / (gridWidth() * zoomX);
	}

	inline function py(sy : Float) {
		return (gridHeight() - sy - panY) / (gridHeight() * zoomY);
	}

	static inline function near(x0 : Float, y0 : Float, x1 : Float, y1 : Float, distance : Float) {
		return Math.abs(x1 - x0) <= distance && Math.abs(y1 - y0) <= distance;
	}


	function updateButtons() {
		if (playButton == null)
			return;
		var hasOwner = owner != null;
		playButton.toggleAttribute("disabled", !hasOwner);
		speedButton.toggleAttribute("disabled", !hasOwner);
		for (b in seekButtons)
			b.toggleAttribute("disabled", !hasOwner || !isSeekable);
	}

	function openHelp(button : Element) {
		var items : Array<hrt.ui.HuiMenu.MenuItem> = [
			{ label: "Play / Pause", keys: "Space" },
			{ label: "Seek", keys: "Click on the ruler" },
			{ label: "Pan", keys: "Middle / right drag" },
			{ label: "Zoom", keys: "Wheel (Shift: values only, Ctrl: time only)" },
			{ label: "Frame all", keys: "F" },
			{ label: "Select", keys: "Click / drag a box (Shift: add)" },
		];
		if (hasEditableCurves()) {
			items.push({ isSeparator: true });
			items.push({ label: "Add key", keys: "Ctrl + click / double click" });
			items.push({ label: "Edit key", keys: "Double click / right click on a key" });
			items.push({ label: "Move keys", keys: "Drag (Ctrl: snap, Shift: lock time, Alt: lock value)" });
		}
		hide.comp.ContextMenu.createDropdown(button, items);
	}

	function changeSpeed(direction : Int) {
		var speed = getSpeed();
		var index = 0;
		while (index < SPEEDS.length - 1 && SPEEDS[index] < speed)
			index++;
		if (direction > 0 && SPEEDS[index] > speed)
			index--;
		setSpeed(SPEEDS[hxd.Math.iclamp(index + direction, 0, SPEEDS.length - 1)]);
	}

	function openSettings(button : Element) {
		hide.comp.ContextMenu.createDropdown(button, [
			{ label: "Units", menu: [
				{ label: "Frames", radio: () -> unit == Frame, click: () -> setUnit(Frame) },
				{ label: "Seconds", radio: () -> unit == Second, click: () -> setUnit(Second) },
			]}
		]);
	}

	function switchUnit() {
		setUnit(unit == Second ? Frame : Second);
	}


	function boxSelect(e : PointerEvent, add : Bool) {
		var initialMarkers = add ? selectedMarkers.copy() : [];
		var initialKeys = add ? selectedKeys.copy() : [];
		var x0 = sxFromEvent(e);
		var y0 = syFromEvent(e);
		drag(rightPanel, e, (e : PointerEvent) -> {
			var x1 = sxFromEvent(e);
			var y1 = syFromEvent(e);
			selectionBox = { x0: Math.min(x0, x1), y0: Math.min(y0, y1), x1: Math.max(x0, x1), y1: Math.max(y0, y1) };

			var keySel = initialKeys.copy();
			for (c in curves) {
				if (c.data == null)
					continue;
				for (k in c.data.keys) {
					var kx = sx(k.time);
					var ky = sy(k.value);
					if (kx >= selectionBox.x0 && kx <= selectionBox.x1 && ky >= selectionBox.y0 && ky <= selectionBox.y1 && !keySel.contains(k))
						keySel.push(k);
				}
			}

			var rect = rightPanel.getBoundingClientRect();
			var left = rect.left + selectionBox.x0;
			var right = rect.left + selectionBox.x1;
			var top = rect.top + rulerHeight + selectionBox.y0;
			var bottom = rect.top + rulerHeight + selectionBox.y1;
			function overlaps(el : Element) {
				var r = el.getBoundingClientRect();
				return r.right >= left && r.left <= right && r.bottom >= top && r.top <= bottom;
			}
			var markerSel = initialMarkers.copy();
			for (m in markers) {
				if (m.element != null && overlaps(m.element.firstElementChild) && !markerSel.contains(m))
					markerSel.push(m);
			}
			setSelection(markerSel, keySel);
		}, (moved) -> {
			selectionBox = null;
			if (!moved)
				setSelection(initialMarkers, initialKeys);
			refresh();
		});
	}

	function setSelection(markerSel : Array<Marker>, keySel : Array<CurveKey>) {
		selectedMarkers = markerSel;
		selectedKeys = keySel;
		for (m in markers)
			m.element?.classList.toggle("selected", selectedMarkers.contains(m));
		refresh();
	}

	function selectAll() {
		setSelection(markers.copy(), [for (c in curves) if (c.data != null) for (k in c.data.keys) k]);
	}

	function deleteSelection() {
		if (selectedKeys.length > 0)
			deleteKeys(selectedKeys.copy());
		if (selectedMarkers.length == 0)
			return;
		var deleted = [for (m in selectedMarkers) ({ name: m.name, frame: m.frame } : Marker)];
		setSelection([], selectedKeys);
		onDelete(deleted);
	}


	function onWheel(e : WheelEvent) {
		e.preventDefault();
		var mouseX = sxFromEvent(e);
		var mouseY = syFromEvent(e);
		var timeX = px(mouseX);
		var valueY = py(mouseY);

		var factor = Math.pow(ZOOM_SPEED, e.deltaY > 0 ? -1 : 1);
		if (!e.shiftKey)
			zoomX = hxd.Math.clamp(zoomX * factor, MIN_ZOOM, MAX_ZOOM);
		if (hasYAxis && !e.ctrlKey)
			zoomY = hxd.Math.clamp(zoomY * factor, MIN_ZOOM, MAX_ZOOM);

		panX = mouseX - timeX * gridWidth() * zoomX;
		if (hasYAxis)
			panY = gridHeight() - mouseY - valueY * gridHeight() * zoomY;
		refresh();
	}

	function onFilterKeyDown(e : KeyboardEvent) {
		e.stopPropagation();
		if (e.key == "Escape")
			setFilter("");
	}

	function onRightPanelPointerDown(e : PointerEvent) {
		if (e.button > 2)
			return;
		e.preventDefault();
		rightPanel.setPointerCapture(e.pointerId);

		if (syFromEvent(e) < 0) {
			setTime(px(sxFromEvent(e)));
			rightPanel.onpointermove = (e : PointerEvent) -> setTime(px(sxFromEvent(e)));
			rightPanel.onlostpointercapture = (_) -> {
				rightPanel.onpointermove = null;
				rightPanel.onlostpointercapture = null;
			};
			return;
		}

		if (e.button == 0) {
			onGridPointerDown(e);
			return;
		}

		var startX = e.clientX;
		var startY = e.clientY;
		var startPanX = panX;
		var startPanY = panY;
		var isDragging = false;
		rightPanel.onpointermove = (e : PointerEvent) -> {
			if (Math.abs(e.clientX - startX) + Math.abs(e.clientY - startY) > DRAG_THRESHOLD)
				isDragging = true;
			if (!isDragging)
				return;
			panX = startPanX + (e.clientX - startX);
			if (hasYAxis)
				panY = startPanY - (e.clientY - startY);
			refresh();
		};
		rightPanel.onpointerup = (e : PointerEvent) -> {
			if (isDragging)
				return;
			if (e.button == 2)
				onContextMenu(e);
		};
		rightPanel.onlostpointercapture = (_) -> {
			rightPanel.onpointermove = null;
			rightPanel.onpointerup = null;
			rightPanel.onlostpointercapture = null;
		};
	}

	function onGridPointerDown(e : PointerEvent) {
		var x = sxFromEvent(e);
		var y = syFromEvent(e);

		for (k in selectedKeys) {
			for (h in k.handles()) {
				if (near(x, y, sx(k.time + h.dt), sy(k.value + h.dv), HIT_DISTANCE)) {
					dragHandle(e, k, h);
					return;
				}
			}
		}

		var key = getKeyAt(x, y);
		if (key != null) {
			if (e.shiftKey || e.ctrlKey) {
				var sel = selectedKeys.copy();
				if (!sel.remove(key))
					sel.push(key);
				setSelection(selectedMarkers, sel);
				return;
			}
			if (!selectedKeys.contains(key))
				setSelection([], [key]);
			dragKeys(e, key);
			return;
		}

		if (e.ctrlKey && hasEditableCurves()) {
			addKeyAt(x, y);
			return;
		}

		boxSelect(e, e.shiftKey);
	}

	function onRightPanelDoubleClick(e : MouseEvent) {
		var x = sxFromEvent(e);
		var y = syFromEvent(e);
		if (y < 0 || e.button != 0)
			return;
		var key = getKeyAt(x, y);
		if (key != null)
			editKey(key, e.clientX, e.clientY);
		else if (hasEditableCurves())
			addKeyAt(x, y);
	}

	function onContextMenu(e : MouseEvent) {
		var x = sxFromEvent(e);
		var y = syFromEvent(e);
		var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
		var key = getKeyAt(x, y);
		if (key != null) {
			if (!selectedKeys.contains(key))
				setSelection([], [key]);
			var keys = selectedKeys.copy();
			items.push({ label: keys.length > 1 ? "Delete keys" : "Delete key", keys: "Delete", click: () -> deleteKeys(keys) });
			items.push({ label: "Edit key", keys: "Double click", click: () -> editKey(key, e.clientX, e.clientY), enabled: keys.length == 1 });
			items.push({ isSeparator: true });
			for (mode in [CurveKeyMode.Aligned, CurveKeyMode.Free, CurveKeyMode.Linear, CurveKeyMode.Constant]) {
				items.push({
					label: ["Aligned", "Free", "Linear", "Constant"][(cast mode : Int)],
					radio: () -> keys.foreach(k -> k.mode == mode),
					click: () -> {
						var edit = beginCurvesEdit();
						for (k in keys)
							k.mode = mode;
						commitCurvesEdit(edit);
					},
				});
			}
		}
		else {
			if (hasEditableCurves() && y >= 0)
				items.push({ label: "Add key", keys: "Ctrl + click", click: () -> addKeyAt(x, y) });
			for (i in contextMenu(timeToFrame(px(x))))
				items.push(i);
		}
		if (items.length == 0)
			return;
		hide.comp.ContextMenu.createFromPoint(e.clientX, e.clientY, items);
	}


	function redraw() {
		needRedraw = false;
		readStyle();
		if (needFrameAll) {
			needFrameAll = false;
			frameAllInternal();
		}
		drawGrid();

		for (r in rows) {
			if (r.element == null) {
				r.element = document.createDivElement();
				r.element.className = "row";
				r.element.append(r.content);
				leftPanel.append(r.element);
			}
		}
		for (m in markers) {
			if (m.element == null) {
				var el = document.createDivElement();
				el.className = "marker";
				m.element = el;
				content.append(el);

				hide.html.Html.build(el,
					<hide-icon icon={HideRes.icon.diamond}/>
				);

				var label = document.createSpanElement();
				label.className = "label";
				label.textContent = m.name;
				el.append(label);

				el.onpointerdown = (e : PointerEvent) -> {
					if (e.button != 0)
						return;
					e.stopPropagation();
					el.setPointerCapture(e.pointerId);

					var isMultiSelect = e.ctrlKey || e.shiftKey;
					var wasSelected = selectedMarkers.contains(m);
					if (isMultiSelect) {
						var sel = selectedMarkers.copy();
						if (!sel.remove(m))
							sel.push(m);
						setSelection(sel, selectedKeys);
					}
					else if (!wasSelected)
						setSelection([m], []);

					var moved = selectedMarkers.contains(m) ? selectedMarkers.copy() : [];
					var oldMarkers = [for (s in moved) ({ name: s.name, frame: s.frame } : Marker)];
					var minDelta = -MAX_FRAME;
					var maxDelta = MAX_FRAME;
					for (s in moved) {
						minDelta = hxd.Math.imax(minDelta, -s.frame);
						maxDelta = hxd.Math.imin(maxDelta, timeToFrame(duration) - s.frame);
					}

					var grabOffset = px(sxFromEvent(e)) - frameToTime(m.frame);
					var startFrame = m.frame;
					el.onpointermove = (e : PointerEvent) -> {
						var delta = hxd.Math.iclamp(timeToFrame(px(sxFromEvent(e)) - grabOffset) - startFrame, minDelta, maxDelta);
						for (i => s in moved)
							s.frame = oldMarkers[i].frame + delta;
						refresh();
					};
					el.onlostpointercapture = (_) -> {
						el.onpointermove = null;
						el.onlostpointercapture = null;
						if (m.frame != startFrame)
							onChange(oldMarkers, [for (s in moved) ({ name: s.name, frame: s.frame } : Marker)]);
						else if (!isMultiSelect && wasSelected)
							setSelection([m], []);
					};
				};

				el.ondblclick = (e : MouseEvent) -> {
					e.stopPropagation();
					renameMarker(m, label);
				};
			}
			m.element.classList.toggle("selected", selectedMarkers.contains(m));
			m.element.style.left = '${sx(frameToTime(m.frame))}px';
		}

		var sorted = markers.copy();
		sorted.sort((a, b) -> b.frame - a.frame);
		var placed : Array<{ x : Float, row : Int }> = [];
		for (m in sorted) {
			var x = sx(frameToTime(m.frame));
			var right = x + m.element.lastElementChild.getBoundingClientRect().width + LABEL_SPACING;
			var row = 0;
			for (p in placed) {
				if (p.x >= x && p.x <= right)
					row = hxd.Math.imax(row, p.row + 1);
			}
			placed.push({ x: x, row: row });
			m.element.style.setProperty("--label-row", '$row');
		}

		drawCurves();
	}

	function drawGrid() {
		var width = rightPanel.clientWidth;
		var height = rightPanel.clientHeight;
		var ratio = window.devicePixelRatio;
		grid.width = Math.round(width * ratio);
		grid.height = Math.round(height * ratio);

		var style = window.getComputedStyle(rightPanel);
		var lineColor = style.getPropertyValue("--grid-color");
		var originColor = style.getPropertyValue("--grid-origin-color");
		var rulerColor = style.getPropertyValue("--ruler-background");
		var outsideColor = style.getPropertyValue("--outside-color");

		var ctx = grid.getContext2d();
		ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
		ctx.clearRect(0, 0, width, height);
		ctx.font = style.fontSize + " " + style.fontFamily;
		ctx.textBaseline = "middle";

		if (duration > 0) {
			ctx.fillStyle = outsideColor;
			var start = hxd.Math.clamp(sx(0), 0, width);
			var end = hxd.Math.clamp(sx(duration), 0, width);
			ctx.fillRect(0, rulerHeight, start, height - rulerHeight);
			ctx.fillRect(end, rulerHeight, width - end, height - rulerHeight);
		}

		var s = unitScale();
		var minX = px(0);
		var maxX = px(width);
		hstep = getStep((maxX - minX) * s, unit == Second ? MIN_STEP : 1., Math.max(2, width / minHorizontalLabelSpacing)) / s;
		drawLines(ctx, false, minX, maxX, hstep, lineColor, originColor);

		if (hasYAxis) {
			var minY = py(gridHeight());
			var maxY = py(0);
			vstep = getStep(maxY - minY, MIN_STEP, Math.max(2, gridHeight() / minVerticalLabelSpacing));
			drawLines(ctx, true, minY, maxY, vstep, lineColor, originColor);

			ctx.fillStyle = style.color;
			ctx.textAlign = "left";
			for (i in Math.floor(minY / vstep)...Math.ceil(maxY / vstep) + 1) {
				var v = i * vstep;
				ctx.fillText(Std.string(hxd.Math.fmt(v)), 5, rulerHeight + sy(v));
			}
		}

		if (duration > 0) {
			ctx.fillStyle = originColor;
			ctx.fillRect(sx(duration) - 1, rulerHeight, 2, height - rulerHeight);
		}

		ctx.fillStyle = rulerColor;
		ctx.fillRect(0, 0, width, rulerHeight);
		ctx.fillStyle = style.color;
		ctx.textAlign = "center";
		for (i in Math.floor(minX / hstep)...Math.ceil(maxX / hstep) + 1) {
			var t = i * hstep;
			ctx.fillText(Std.string(hxd.Math.fmt(t * s)), sx(t), rulerHeight / 2);
		}
	}

	function drawLines(ctx : CanvasRenderingContext2D, isHorizontal : Bool, min : Float, max : Float, step : Float, color : String, originColor : String) {
		var width = rightPanel.clientWidth;
		var height = gridHeight();
		function line(v : Float, size : Float) {
			var p = isHorizontal ? rulerHeight + sy(v) : sx(v);
			if (isHorizontal)
				ctx.fillRect(0, p - size / 2, width, size);
			else
				ctx.fillRect(p - size / 2, rulerHeight, size, height);
		}

		ctx.fillStyle = color;
		for (i in Math.floor(min / step)...Math.ceil(max / step) + 1) {
			if (i != 0)
				line(i * step, 1);
		}

		ctx.fillStyle = originColor;
		line(0, 1);
	}

	function svgElement(parent : Element, name : String, attributes : haxe.DynamicAccess<Dynamic>, ?className : String) : Element {
		var el : Element = cast document.createElementNS(SVG_NS, name);
		for (k => v in attributes)
			el.setAttribute(k, Std.string(v));
		if (className != null)
			el.setAttribute("class", className);
		parent.appendChild(el);
		return el;
	}

	function drawCurves() {
		curvesSvg.innerHTML = "";
		var allKeys = [for (c in curves) if (c.data != null) for (k in c.data.keys) k];
		selectedKeys = selectedKeys.filter(k -> allKeys.contains(k));
		if (curves.length == 0 && selectionBox == null)
			return;

		var width = gridWidth();
		var x0 = Math.max(sx(0), 0.);
		for (c in curves) {
			if (x0 >= width)
				break;
			var points = new StringBuf();
			var x = x0;
			while (true) {
				var v = c.getValue(px(x));
				if (Math.isFinite(v)) {
					points.add(hxd.Math.fmt(x));
					points.add(",");
					points.add(hxd.Math.fmt(sy(v)));
					points.add(" ");
				}
				if (x >= width)
					break;
				x = Math.min(x + PIXELS_PER_SAMPLE, width);
			}
			var line = svgElement(curvesSvg, "polyline", { points: points.toString(), stroke: colorString(c.color) }, "curve");
			if (c.dashed)
				line.classList.add("dashed");
			if (c.faded)
				line.classList.add("faded");
		}

		for (c in curves) {
			if (c.data == null)
				continue;
			var color = colorString(c.color);
			for (k in c.data.keys) {
				var kx = sx(k.time);
				var ky = sy(k.value);
				var selected = selectedKeys.contains(k);
				if (selected) {
					for (h in k.handles()) {
						var hx = sx(k.time + h.dt);
						var hy = sy(k.value + h.dv);
						svgElement(curvesSvg, "line", { x1: kx, y1: ky, x2: hx, y2: hy }, "tangent");
						svgElement(curvesSvg, "circle", { cx: hx, cy: hy, r: handleSize }, "handle");
					}
				}
				var d = keySize;
				var key = svgElement(curvesSvg, "polygon", { points: '${kx},${ky - d} ${kx + d},${ky} ${kx},${ky + d} ${kx - d},${ky}', fill: color }, "key");
				if (selected)
					key.classList.add("selected");
			}
		}

		if (selectionBox != null) {
			svgElement(curvesSvg, "rect", { x: selectionBox.x0, y: selectionBox.y0, width: selectionBox.x1 - selectionBox.x0, height: selectionBox.y1 - selectionBox.y0 }, "selection-box");
		}
	}

	function getStep(range : Float, minStep : Float, maxLabels : Float) : Float {
		var step = minStep;
		var i = 0;
		while (range / step > maxLabels) {
			step *= (i % 3 == 1) ? 2.5 : 2;
			i++;
		}
		return step;
	}

	function drag(el : Element, e : PointerEvent, move : PointerEvent -> Void, end : Bool -> Void) {
		el.setPointerCapture(e.pointerId);
		var startX = e.clientX;
		var startY = e.clientY;
		var moved = false;
		el.onpointermove = (e : PointerEvent) -> {
			if (!moved && Math.abs(e.clientX - startX) + Math.abs(e.clientY - startY) > DRAG_THRESHOLD)
				moved = true;
			if (moved)
				move(e);
		};
		el.onlostpointercapture = (_) -> {
			el.onpointermove = null;
			el.onlostpointercapture = null;
			end(moved);
		};
	}

	function hasEditableCurves() {
		return curves.exists(c -> c.data != null);
	}

	function getKeyCurveData(k : CurveKey) {
		for (c in curves) {
			if (c.data != null && c.data.keys.contains(k))
				return c.data;
		}
		return null;
	}

	function getKeyAt(x : Float, y : Float) : CurveKey {
		var i = curves.length - 1;
		while (i >= 0) {
			var c = curves[i--];
			if (c.data == null)
				continue;
			for (k in c.data.keys) {
				if (near(x, y, sx(k.time), sy(k.value), HIT_DISTANCE))
					return k;
			}
		}
		return null;
	}

	function fixKey(data : hrt.impl.Curve, key : CurveKey) {
		var index = data.keys.indexOf(key);
		var prev = data.keys[index - 1];
		var next = data.keys[index + 1];
		switch (key.mode) {
			case Aligned, Free:
				if (key.prevHandle == null)
					key.prevHandle = new CurveHandle(prev != null ? (prev.time - key.time) / 3 : -0.5, 0);
				if (key.nextHandle == null)
					key.nextHandle = new CurveHandle(next != null ? (next.time - key.time) / 3 : 0.5, 0);
			case Linear, Constant:
				key.prevHandle = null;
				key.nextHandle = null;
		}
		if (key.time < 0)
			key.time = 0;
	}

	function addKeyAt(x : Float, y : Float) {
		var t = Math.max(px(x), 0.);
		var near = getCurveAt(x, y);
		var targets = near != null ? [near] : [for (c in curves) if (c.data != null) c];
		var added = [];
		var edit = beginCurvesEdit();
		for (c in targets) {
			if (!added.exists(k -> getKeyCurveData(k) == c.data))
				added.push(c.data.addKey(t, near != null ? py(y) : c.data.getVal(t)));
		}
		commitCurvesEdit(edit);
		setSelection([], added);
	}

	function deleteKeys(keys : Array<CurveKey>) {
		var edit = beginCurvesEdit();
		for (d in edit.datas) {
			var kept = d.keys.filter(k -> !keys.contains(k));
			// a curve keeps a key
			if (kept.length == 0 && d.keys.length > 0)
				kept = [d.keys[0]];
			d.keys = kept;
		}
		commitCurvesEdit(edit);
		setSelection(selectedMarkers, []);
	}

	function dragKeys(e : PointerEvent, k : CurveKey) {
		var keys = selectedKeys.copy();
		var start = [for (key in keys) { time: key.time, value: key.value }];
		var grabbedStart = start[keys.indexOf(k)];
		var minDt = Math.NEGATIVE_INFINITY;
		var maxDt = Math.POSITIVE_INFINITY;
		for (j => key in keys) {
			var data = getKeyCurveData(key);
			if (data == null)
				continue;
			var i = data.keys.indexOf(key);
			var prev = data.keys[i - 1];
			var next = data.keys[i + 1];
			if (prev == null || !keys.contains(prev))
				minDt = Math.max(minDt, (prev?.time ?? 0.) - start[j].time);
			if (next != null && !keys.contains(next))
				maxDt = Math.min(maxDt, next.time - start[j].time);
		}
		var t0 = px(sxFromEvent(e));
		var v0 = py(syFromEvent(e));
		var edit = beginCurvesEdit();
		drag(rightPanel, e, (e : PointerEvent) -> {
			var t = grabbedStart.time + px(sxFromEvent(e)) - t0;
			var v = grabbedStart.value + py(syFromEvent(e)) - v0;
			if (e.ctrlKey) {
				t = Math.round(t * 10) / 10;
				v = Math.round(v * 10) / 10;
			}
			var dt = e.shiftKey ? 0. : hxd.Math.clamp(t - grabbedStart.time, minDt, maxDt);
			var dv = e.altKey ? 0. : v - grabbedStart.value;
			for (j => key in keys) {
				key.time = start[j].time + dt;
				key.value = start[j].value + dv;
			}
			updateCurvesEdit(edit);
		}, (moved) -> if (moved) commitCurvesEdit(edit));
	}

	function dragHandle(e : PointerEvent, k : CurveKey, h : CurveHandle) {
		var isNext = h == k.nextHandle;
		var other = isNext ? k.prevHandle : k.nextHandle;
		var otherLength = other == null ? 0. : hxd.Math.distance(sx(k.time + other.dt) - sx(k.time), sy(k.value + other.dv) - sy(k.value));
		var edit = beginCurvesEdit();
		drag(rightPanel, e, (e : PointerEvent) -> {
			var kx = sx(k.time);
			var ky = sy(k.value);
			var x = isNext ? Math.max(sxFromEvent(e), kx) : Math.min(sxFromEvent(e), kx);
			var y = syFromEvent(e);
			h.dt = px(x) - k.time;
			h.dv = py(y) - k.value;
			if (k.mode == CurveKeyMode.Aligned && other != null) {
				var dx = x - kx;
				var dy = y - ky;
				var len = hxd.Math.distance(dx, dy);
				if (len > 1e-6) {
					other.dt = px(kx - dx / len * otherLength) - k.time;
					other.dv = py(ky - dy / len * otherLength) - k.value;
				}
			}
			updateCurvesEdit(edit);
		}, (moved) -> if (moved) commitCurvesEdit(edit));
	}

	function editKey(k : CurveKey, clientX : Float, clientY : Float) {
		var data = getKeyCurveData(k);
		if (data == null)
			return;
		setSelection([], [k]);

		var popup = new hide.comp.Popup(element, false);
		function closeOnEnter(e : KeyboardEvent) {
			if (e.key == "Enter")
				popup.close();
		}

		hide.html.Html.build(popup.element.get(0),
			<div class="key-popup">
				<label>
					<span>Time</span>
					<input id="time-input" type="number" step="0.05" value={hxd.Math.fmt(k.time)} onchange={() -> setKey(k, timeInput.valueAsNumber, valueInput.valueAsNumber)} onkeydown={closeOnEnter}/>
				</label>
				<label>
					<span>Value</span>
					<input id="value-input" type="number" step="0.1" value={hxd.Math.fmt(k.value)} onchange={() -> setKey(k, timeInput.valueAsNumber, valueInput.valueAsNumber)} onkeydown={closeOnEnter}/>
				</label>
			</div>
		);
		popup.anchor = { object: Point(clientX + 8, clientY - 20), directionX: EndOutside, directionY: EndOutside };
		timeInput.focus();
		timeInput.select();
	}

	function setKey(k : CurveKey, time : Float, value : Float) {
		if (Math.isNaN(time) || Math.isNaN(value))
			return;
		var data = getKeyCurveData(k);
		var i = data.keys.indexOf(k);
		var edit = beginCurvesEdit();
		k.time = hxd.Math.clamp(time, data.keys[i - 1]?.time ?? 0., data.keys[i + 1]?.time ?? Math.POSITIVE_INFINITY);
		k.value = value;
		commitCurvesEdit(edit);
	}

	function getCurveAt(x : Float, y : Float) {
		var t = px(x);
		for (c in curves) {
			if (c.data != null && Math.abs(sy(c.getValue(t)) - y) <= HIT_DISTANCE)
				return c;
		}
		return null;
	}

	function frameAllInternal() {
		var end = duration;
		for (c in curves) {
			if (c.data != null && c.data.keys.length > 0)
				end = Math.max(end, c.data.keys[c.data.keys.length - 1].time);
		}
		if (end <= 0)
			end = 1.;

		var range = frameToTime(1) + end;
		var w = gridWidth();
		zoomX = hxd.Math.clamp((1 - 2 * FRAME_ALL_PADDING / w) / range, MIN_ZOOM, MAX_ZOOM);
		panX = FRAME_ALL_PADDING;

		if (!hasYAxis || curves.length == 0)
			return;

		var minV = Math.POSITIVE_INFINITY;
		var maxV = Math.NEGATIVE_INFINITY;
		for (c in curves) {
			if (c.data == null || c.data.keys.length == 0)
				continue;
			var r = c.data.getValueRange();
			minV = Math.min(minV, r.min);
			maxV = Math.max(maxV, r.max);
		}
		if (minV > maxV)
			return;
		if (maxV - minV < 1e-6) {
			minV -= 1;
			maxV += 1;
		}

		var h = gridHeight();
		var top = FRAME_ALL_PADDING;
		var bottom = h - FRAME_ALL_PADDING;
		if (bottom <= top)
			return;
		zoomY = hxd.Math.clamp((bottom - top) / ((maxV - minV) * h), MIN_ZOOM, MAX_ZOOM);
		panY = h - bottom - minV * h * zoomY;
	}

	function readStyle() {
		var style = window.getComputedStyle(rightPanel);
		rulerHeight = Std.parseFloat(style.getPropertyValue("--ruler-height"));
		keySize = Std.parseFloat(style.getPropertyValue("--key-size"));
		handleSize = Std.parseFloat(style.getPropertyValue("--handle-size"));
		minHorizontalLabelSpacing = Std.parseFloat(style.getPropertyValue("--min-horizontal-label-spacing"));
		minVerticalLabelSpacing = Std.parseFloat(style.getPropertyValue("--min-vertical-label-spacing"));
	}

	function renameMarker(m : Marker, label : Element) {
		var input = document.createInputElement();
		input.value = m.name;
		label.replaceWith(input);
		input.focus();
		input.select();
		input.onpointerdown = (e : PointerEvent) -> e.stopPropagation();

		var isCanceled = false;
		input.onkeydown = (e : KeyboardEvent) -> {
			e.stopPropagation();
			if (e.key == "Enter")
				input.blur();
			else if (e.key == "Escape") {
				isCanceled = true;
				input.blur();
			}
		};
		input.onblur = () -> {
			input.replaceWith(label);
			if (isCanceled || input.value == "" || input.value == m.name)
				return;
			var oldMarker : Marker = { name: m.name, frame: m.frame };
			m.name = input.value;
			label.textContent = m.name;
			onChange([oldMarker], [{ name: m.name, frame: m.frame }]);
		};
	}


	function beginCurvesEdit() : CurvesEdit {
		var datas = [];
		for (c in curves) {
			if (c.data != null && !datas.contains(c.data))
				datas.push(c.data);
		}
		return { datas: datas, start: [for (d in datas) @:privateAccess d.copyToDynamic(null)] };
	}

	function updateCurvesEdit(edit : CurvesEdit) {
		for (d in edit.datas) {
			for (k in d.keys)
				fixKey(d, k);
		}
		refresh();
		onCurvesEdit();
	}

	function commitCurvesEdit(edit : CurvesEdit) {
		for (d in edit.datas) {
			for (k in d.keys)
				fixKey(d, k);
		}
		refresh();
		var after = [for (d in edit.datas) @:privateAccess d.copyToDynamic(null)];
		if (haxe.Json.stringify(edit.start) != haxe.Json.stringify(after))
			onCurvesChange(edit.datas, edit.start, after);
	}

	static var _ = hide.ui.View.register(Timeline, { position: Bottom });
}
