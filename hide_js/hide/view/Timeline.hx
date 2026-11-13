package hide.view;

import js.Browser.document;
import js.Browser.window;
import js.html.*;

enum Unit {
	Second;
	Frame;
}

enum ClearFlag {
	Full;
	Content;
}

typedef Track = {
	name : String,
	content : Element,
	?element : Element
}

typedef Clip = {
	name : String,
	start : Int,
	end : Int,
	?track : Track,
	?element : Element
}

typedef Marker = {
	name : String,
	frame : Int,
	?track : Track,
	?element : Element
}

class Timeline extends hide.ui.View<{}> {
	static final RULER_HEIGHT = 20;
	static final GRID_SUBDIVISIONS = 5;
	static final GRID_SUB_ALPHA = 0.35;
	static final MIN_STEP = 1e-2;
	static final MAX_LABELS = 21;
	static final MIN_ZOOM = 1e-4;
	static final MAX_ZOOM = 1e4;
	static final ZOOM_SPEED = 1.1;
	static final DRAG_THRESHOLD = 3;
	static final FRAME_ALL_MARGIN = 0.03;
	static final LABEL_SPACING = 6;
	static final MAX_FRAME = 1 << 30;
	static final SPEEDS = [0.125, 0.25, 0.5, 1., 2., 4., 8.];

	public var owner(default, set) : hide.ui.View<Dynamic>;
	public var isSeekable(default, set) : Bool = true;
	public var unit(default, null) : Unit = Second;
	public var hasYAxis(default, null) : Bool = false;
	public var framerate(default, null) : Float = 60.;

	var tracks : Array<Track> = [];
	var clips : Array<Clip> = [];
	var markers : Array<Marker> = [];
	var selection : Array<Marker> = [];
	var needRefresh = true;
	var needFrameAll = false;

	var zoomX = 1.;
	var zoomY = 1.;
	var panX = 0.;
	var panY = 0.;
	var hstep = MIN_STEP;
	var vstep = MIN_STEP;
	var wasPaused : Null<Bool>;
	var shownSpeed : Null<Float>;
	var resizeObserver : hide.comp.ResizeObserver;

	var leftPanel : Element;
	var rightPanel : Element;
	var grid : CanvasElement;
	var content : Element;
	var playhead : Element;
	var time : SpanElement;
	var playButton : hide.html.comp.Button;
	var speedButton : hide.html.comp.Button;
	var seekButtons : Array<hide.html.comp.Button> = [];

	override function onDisplay() {
		var root = element.get(0);
		root.innerHTML = "";
		root.classList.add("timeline");
		wasPaused = null;
		shownSpeed = null;

		hide.html.Html.build(root,
			<div class="timeline-root">
				<hide-toolbar>
					<hide-group>
						<hide-button id="start-button" title="Go to start" icon={HideRes.icon.fast_rewind} onclick={() -> setTime(0.)}/>
						<hide-button id="previous-button" title="Previous frame" icon={HideRes.icon.skip_previous} onclick={() -> setTime(Math.max(getTime() - frameToTime(1), 0.))}/>
						<hide-button id="play-button" title="Play / Pause" icon={HideRes.icon.play} onclick={() -> setPaused(!isPaused())}/>
						<hide-button id="next-button" title="Next frame" icon={HideRes.icon.skip_next} onclick={() -> setTime(Math.min(getTime() + frameToTime(1), frameToTime(getMaxFrame())))}/>
						<hide-button id="end-button" title="Go to end" icon={HideRes.icon.fast_forward} onclick={() -> setTime(frameToTime(getMaxFrame()))}/>
					</hide-group>
					<hide-button id="speed-button" title="Playback speed (click: faster, right click: slower)" onclick={() -> changeSpeed(1)} oncontextmenu={(e : MouseEvent) -> { e.preventDefault(); changeSpeed(-1); }}/>
					<hide-button title="Frame all" icon={HideRes.icon.fullscreen} onclick={frameAll}/>
					<hide-button title="Settings" icon={HideRes.icon.settings} onclick={(e : MouseEvent) -> openSettings(cast e.currentTarget)}/>
				</hide-toolbar>
				<hide-split-container class="timeline-body">
					<div id="left-panel" class="left-panel" anchor="previous" size="250"></div>
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
		seekButtons = [startButton, previousButton, nextButton, endButton];
		updateButtons();

		for (t in tracks)
			t.element = null;
		for (c in clips)
			c.element = null;
		for (m in markers)
			m.element = null;

		rightPanel.onwheel = onWheel;
		rightPanel.onpointerdown = onRightPanelPointerDown;
		rightPanel.oncontextmenu = (e : MouseEvent) -> e.preventDefault();

		keys.register("save", () -> onSave());
		keys.register("undo", () -> onUndo());
		keys.register("redo", () -> onRedo());
		keys.register("delete", deleteSelection);
		keys.register("selectAll", () -> setSelection(markers.copy()));
		keys.register("playPause", () -> setPaused(!isPaused()));

		refresh();

		for (m in ide.getViews(Model)) {
			if (m.isActive())
				m.bindTimeline(this);
		}
		for (p in ide.getViews(Prefab)) {
			if (p.isActive())
				p.bindTimeline(this);
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
		needRefresh = true;
		if (owner == null)
			update();
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

	public function clear(flag : ClearFlag = Full) {
		for (t in tracks)
			t.element?.remove();
		for (c in clips)
			c.element?.remove();
		for (m in markers)
			m.element?.remove();
		tracks = [];
		clips = [];
		markers = [];
		selection = [];

		if (flag == Full) {
			owner = null;
			isSeekable = true;
			hasYAxis = false;
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
		}

		refresh();
	}

	public function getTrack(name : String) {
		for (t in tracks) {
			if (t.name == name)
				return t;
		}
		return null;
	}

	public function addTrack(name : String, content : Element) {
		tracks.push({ name: name, content: content });
		refresh();
	}

	public function addClip(name : String, start : Int, end : Int, ?track : String) {
		var c : Clip = { name: name, start: start, end: end };
		if (track != null)
			c.track = getTrack(track);
		clips.push(c);
		refresh();
	}

	public function addMarker(name : String, frame : Int, ?track : String) {
		var m : Marker = { name: name, frame: frame };
		if (track != null)
			m.track = getTrack(track);
		markers.push(m);
		refresh();
	}

	public function removeMarker(name : String, frame : Int) {
		var idx = markers.length - 1;
		while (idx >= 0) {
			var m = markers[idx];
			if (m.name == name && m.frame == frame) {
				markers.remove(m);
				m.element?.remove();
				selection.remove(m);
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
		setSelection(sel);
	}

	public function update() {
		if (!isActive())
			return;

		var ratio = window.devicePixelRatio;
		if (grid.width != Math.round(rightPanel.clientWidth * ratio) || grid.height != Math.round(rightPanel.clientHeight * ratio))
			needRefresh = true;
		if (needRefresh)
			refreshInternal();

		var t = getTime();
		var s = unitScale();
		var decimals = hxd.Math.imax(0, Math.ceil(-Math.log(hstep * s) / Math.log(10) - 1e-6));
		var f = Math.pow(10, decimals);
		time.textContent = '${Math.round(t * s * f) / f}';
		playhead.style.left = '${sx(t)}px';

		var paused = isPaused();
		if (paused != wasPaused) {
			wasPaused = paused;
			playButton.icon = Std.string(paused ? HideRes.icon.play : HideRes.icon.pause);
		}

		var speed = getSpeed();
		if (speed != shownSpeed) {
			shownSpeed = speed;
			speedButton.label = 'x$speed';
		}
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

	function set_owner(v : hide.ui.View<Dynamic>) {
		owner = v;
		updateButtons();
		return v;
	}

	function set_isSeekable(v : Bool) {
		isSeekable = v;
		updateButtons();
		return v;
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
		return rightPanel.clientHeight - RULER_HEIGHT;
	}

	inline function sx(px : Float) {
		return px * gridWidth() * zoomX + panX;
	}

	inline function sy(py : Float) {
		return gridHeight() - (py * gridHeight() * zoomY + panY);
	}

	inline function px(sx : Float) {
		return (sx - panX) / (gridWidth() * zoomX);
	}

	inline function py(sy : Float) {
		return (gridHeight() - sy - panY) / (gridHeight() * zoomY);
	}

	function localX(e : MouseEvent) {
		return e.clientX - rightPanel.getBoundingClientRect().left;
	}

	function localY(e : MouseEvent) {
		return e.clientY - rightPanel.getBoundingClientRect().top - RULER_HEIGHT;
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

	function getMaxFrame() {
		var max = 0;
		for (c in clips) {
			if (c.track != null && c.end > max)
				max = c.end;
		}
		return max;
	}

	function getStep(range : Float, minStep : Float) : Float {
		var step = minStep;
		var i = 0;
		while (range / step > MAX_LABELS) {
			step *= (i % 3 == 1) ? 2.5 : 2;
			i++;
		}
		return step;
	}

	function setSelection(sel : Array<Marker>) {
		selection = sel;
		for (m in markers)
			m.element?.classList.toggle("selected", selection.contains(m));
	}

	function deleteSelection() {
		if (selection.length == 0)
			return;
		var deleted = [for (m in selection) ({ name: m.name, frame: m.frame } : Marker)];
		setSelection([]);
		onDelete(deleted);
	}

	function openSettings(button : Element) {
		hide.comp.ContextMenu.createDropdown(button, [
			{ label: "Units", menu: [
				{ label: "Frames", radio: () -> unit == Frame, click: () -> setUnit(Frame) },
				{ label: "Seconds", radio: () -> unit == Second, click: () -> setUnit(Second) },
			]}
		]);
	}

	function onWheel(e : WheelEvent) {
		e.preventDefault();
		var mouseX = localX(e);
		var mouseY = localY(e);
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

	function onRightPanelPointerDown(e : PointerEvent) {
		if (e.button > 2)
			return;
		e.preventDefault();
		rightPanel.setPointerCapture(e.pointerId);

		if (localY(e) < 0) {
			setTime(px(localX(e)));
			rightPanel.onpointermove = (e : PointerEvent) -> setTime(px(localX(e)));
			rightPanel.onlostpointercapture = (_) -> {
				rightPanel.onpointermove = null;
				rightPanel.onlostpointercapture = null;
			};
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
			if (e.button == 0)
				setSelection([]);
			else if (e.button == 2)
				onContextMenu(e);
		};
		rightPanel.onlostpointercapture = (_) -> {
			rightPanel.onpointermove = null;
			rightPanel.onpointerup = null;
			rightPanel.onlostpointercapture = null;
		};
	}

	function onContextMenu(e : MouseEvent) {
		var items = contextMenu(timeToFrame(px(localX(e))));
		if (items.length == 0)
			return;
		hide.comp.ContextMenu.createFromPoint(e.clientX, e.clientY, items);
	}

	function refreshInternal() {
		needRefresh = false;
		if (needFrameAll) {
			needFrameAll = false;
			var duration = frameToTime(getMaxFrame() + 1);
			if (duration > 0) {
				zoomX = hxd.Math.clamp((1 - 2 * FRAME_ALL_MARGIN) / duration, MIN_ZOOM, MAX_ZOOM);
				panX = gridWidth() * FRAME_ALL_MARGIN;
			}
		}
		drawGrid();

		for (t in tracks) {
			if (t.element == null) {
				t.element = document.createDivElement();
				t.element.className = "track";
				t.element.append(t.content);
				leftPanel.append(t.element);
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
					var wasSelected = selection.contains(m);
					if (isMultiSelect) {
						var sel = selection.copy();
						if (!sel.remove(m))
							sel.push(m);
						setSelection(sel);
					}
					else if (!wasSelected)
						setSelection([m]);

					var moved = selection.contains(m) ? selection.copy() : [];
					var oldMarkers = [for (s in moved) ({ name: s.name, frame: s.frame } : Marker)];
					var minDelta = -MAX_FRAME;
					var maxDelta = MAX_FRAME;
					for (s in moved) {
						var clip = getTrackClip(s.track);
						minDelta = hxd.Math.imax(minDelta, (clip?.start ?? 0) - s.frame);
						if (clip != null)
							maxDelta = hxd.Math.imin(maxDelta, clip.end - s.frame);
					}

					var grabOffset = px(localX(e)) - frameToTime(m.frame);
					var startFrame = m.frame;
					el.onpointermove = (e : PointerEvent) -> {
						var delta = hxd.Math.iclamp(timeToFrame(px(localX(e)) - grabOffset) - startFrame, minDelta, maxDelta);
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
							setSelection([m]);
					};
				};

				el.ondblclick = (e : MouseEvent) -> {
					e.stopPropagation();
					renameMarker(m, label);
				};
			}
			m.element.classList.toggle("selected", selection.contains(m));
			m.element.style.left = '${sx(frameToTime(m.frame))}px';
		}

		var sorted = markers.copy();
		sorted.sort((a, b) -> b.frame - a.frame);
		var placed : Array<{ track : Track, x : Float, row : Int }> = [];
		for (m in sorted) {
			var x = sx(frameToTime(m.frame));
			var right = x + m.element.lastElementChild.getBoundingClientRect().width + LABEL_SPACING;
			var row = 0;
			for (p in placed) {
				if (p.track == m.track && p.x >= x && p.x <= right)
					row = hxd.Math.imax(row, p.row + 1);
			}
			placed.push({ track: m.track, x: x, row: row });
			m.element.style.setProperty("--label-row", '$row');
		}

		var contentTop = content.getBoundingClientRect().top;
		function trackY(t : Track) {
			return t == null ? 0. : t.element.getBoundingClientRect().top - contentTop;
		}

		for (c in clips) {
			if (c.element == null) {
				c.element = document.createDivElement();
				c.element.className = "clip";
				c.element.textContent = c.name;
				content.append(c.element);
			}
			var start = sx(frameToTime(c.start));
			c.element.style.left = '${start}px';
			c.element.style.width = '${sx(frameToTime(c.end)) - start}px';
			c.element.style.top = '${trackY(c.track)}px';
		}

		for (m in markers)
			m.element.style.top = '${trackY(m.track)}px';
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

		var ctx = grid.getContext2d();
		ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
		ctx.clearRect(0, 0, width, height);
		ctx.font = style.fontSize + " " + style.fontFamily;
		ctx.textBaseline = "middle";

		var s = unitScale();
		var minX = px(0);
		var maxX = px(width);
		hstep = getStep((maxX - minX) * s, unit == Second ? MIN_STEP : 1.) / s;
		drawLines(ctx, false, minX, maxX, hstep, lineColor, originColor);

		if (hasYAxis) {
			var minY = py(gridHeight());
			var maxY = py(0);
			vstep = getStep(maxY - minY, MIN_STEP);
			drawLines(ctx, true, minY, maxY, vstep, lineColor, originColor);

			ctx.fillStyle = style.color;
			ctx.textAlign = "left";
			for (i in Math.floor(minY / vstep)...Math.ceil(maxY / vstep) + 1) {
				var v = i * vstep;
				ctx.fillText(Std.string(hxd.Math.fmt(v)), 5, RULER_HEIGHT + sy(v));
			}
		}

		ctx.fillStyle = rulerColor;
		ctx.fillRect(0, 0, width, RULER_HEIGHT);
		ctx.fillStyle = style.color;
		ctx.textAlign = "center";
		for (i in Math.floor(minX / hstep)...Math.ceil(maxX / hstep) + 1) {
			var t = i * hstep;
			ctx.fillText(Std.string(hxd.Math.fmt(t * s)), sx(t), RULER_HEIGHT / 2);
		}
	}

	function drawLines(ctx : CanvasRenderingContext2D, isHorizontal : Bool, min : Float, max : Float, step : Float, color : String, originColor : String) {
		var width = rightPanel.clientWidth;
		var height = gridHeight();
		function line(v : Float, size : Float) {
			var p = isHorizontal ? RULER_HEIGHT + sy(v) : sx(v);
			if (isHorizontal)
				ctx.fillRect(0, p - size / 2, width, size);
			else
				ctx.fillRect(p - size / 2, RULER_HEIGHT, size, height);
		}

		var subStep = step / GRID_SUBDIVISIONS;
		var subSpacing = Math.abs(isHorizontal ? sy(0) - sy(subStep) : sx(subStep) - sx(0));
		var subFade = hxd.Math.clamp((subSpacing - 4) / 4);
		ctx.fillStyle = color;
		if (subFade > 0) {
			ctx.globalAlpha = subFade * GRID_SUB_ALPHA;
			for (i in Math.floor(min / subStep)...Math.ceil(max / subStep) + 1) {
				if (i % GRID_SUBDIVISIONS != 0)
					line(i * subStep, 1);
			}
		}

		ctx.globalAlpha = 1;
		for (i in Math.floor(min / step)...Math.ceil(max / step) + 1) {
			if (i != 0)
				line(i * step, 1);
		}

		ctx.fillStyle = originColor;
		line(0, 2);
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

	function getTrackClip(t : Track) {
		if (t == null)
			return null;
		for (c in clips) {
			if (c.track == t)
				return c;
		}
		return null;
	}

	static var _ = hide.ui.View.register(Timeline, { position: Bottom });
}
