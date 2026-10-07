package hide.view;
import hrt.ui.*;

enum Unit {
	Second;
	Frame;
	Timecode;
}

enum ClearFlag {
	Full;
	LeftPanel;
	RightPanel;
}

typedef Track = {
	name : String,
	content : HuiElement,
	?element : HuiElement
}

typedef Clip = {
	name : String,
	start : Int,
	end : Int,
	?track : Track,
	?element : HuiElement
}

typedef Marker = {
	name : String,
	frame : Int,
	?track : Track,
	?element : HuiElement
}

class GridShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			var position : Vec2;
		}

		@param var useYAxis : Bool;
		@param var lineColor : Vec3;
		@param var stepOrigin : Vec2;
		@param var stepSpacing : Vec2;
		@param var stepWidth : Float;
		@param var subdivisions : Float;
		@param var subAlpha : Float;
		@param var originColor : Vec3;
		@param var originWidth : Float;

		var absolutePosition : Vec4;
		var pixelColor : Vec4;

		function lineMask(dist : Float, width : Float) : Float {
			return 1.0 - smoothstep(width * 0.5 - 0.5, width * 0.5 + 0.5, dist);
		}

		function stepLines(p : Float, origin : Float, spacing : Float) : Float {
			var dist = abs(fract((p - origin) / spacing + 0.5) - 0.5) * spacing;
			return lineMask(dist, stepWidth);
		}

		function fragment() {
			var major = max(
				stepLines(absolutePosition.x, stepOrigin.x, stepSpacing.x),
				useYAxis ? stepLines(absolutePosition.y, stepOrigin.y, stepSpacing.y) : 0.);

			var subSpacing = stepSpacing / subdivisions;
			var subFade = saturate((subSpacing - 4.0) / 4.0);
			var minor = max(
				stepLines(absolutePosition.x, stepOrigin.x, subSpacing.x) * subFade.x,
				useYAxis ? stepLines(absolutePosition.y, stepOrigin.y, subSpacing.y) * subFade.y : 0.);

			var origin = max(
				lineMask(abs(absolutePosition.x - stepOrigin.x), originWidth),
				useYAxis ? lineMask(abs(absolutePosition.y - stepOrigin.y), originWidth) : 0.);

			pixelColor.rgb = mix(lineColor, originColor, origin);
			pixelColor.a = max(max(major, minor * subAlpha), origin);
		}
	}
}

class Timeline extends HuiView<{path: String, mode: hrt.ui.HuiFileBrowser.BrowserMode}> {
	static var SRC =
		<timeline>
			<hui-split-container id="container" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal} anchor-to={hrt.ui.HuiSplitContainer.AnchorTo.End} save-display-key="timeline-panel-split">
				<hui-element id="left-panel"></hui-element>
				<hui-element id="right-panel">
					<hui-element class="vertical">
						<hui-element id="timer-track"></hui-element>
						<hui-element id="grid">
							<hui-element id="content"></hui-element>
						</hui-element>
					</hui-element>
					<hui-element id="playhead">
						<hui-element id="head">
							<hui-text("0.4") id="time"/>
						</hui-element>
						<hui-element id="body"></hui-element>
					</hui-element>
				</hui-element>
			</hui-split-container>
		</timeline>

	static final GRID_COLOR = 0x4C4C4C;
	static final GRID_ORIGIN_COLOR = 0x7E7E7E;
	static final GRID_SUB_ALPHA = 0.35;
	static final GRID_ORIGIN_WIDTH = 2;
	static final GRID_STEP_WIDTH = 1;
	static final GRID_SUBDIVISIONS = 5;
	static final MIN_STEP = 1e-2;
	static final MAX_LABELS = 21;
	static final MIN_ZOOM = 1e-4;
	static final MAX_ZOOM = 1e4;
	static final ZOOM_SPEED = 1.1;

	public var unit : Unit = Unit.Second;
	public var useYAxis : Bool = true;
	public var framerate : Float = 60.;

	var tracks : Array<Track> = [];
	var clips : Array<Clip> = [];
	var markers : Array<Marker> = [];
	var needRefresh = true;
	var selection : Array<Marker> = [];

	var gridShader : GridShader = null;
	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);
	var onPanDrag : (e : hxd.Event) -> Void;
	var labels = [];
	var hstep = MIN_STEP;
	var vstep = MIN_STEP;

	public inline function frameToTime(f : Int) { return f / framerate; }
	public inline function timeToFrame(t : Float) { return hxd.Math.round(t * framerate); }
	inline function sx(px : Float) { return px * grid.calculatedWidth * zoom.x + pan.x; }
	inline function sy(py : Float) { return grid.calculatedHeight - (py * grid.calculatedHeight * zoom.y + pan.y); }
	inline function px(sx : Float) { return (sx - pan.x) / (grid.calculatedWidth * zoom.x); }
	inline function py(sy : Float) { return (grid.calculatedHeight - sy - pan.y) / (grid.calculatedHeight * zoom.y); }

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		registerCommand(HuiCommands.save, FocusedView, () -> { onSave();});
		registerCommand(HuiCommands.delete, FocusedView, () -> {
			if (selection.length == 0) return;
			onDelete([ for (m in selection) { name: m.name, frame: m.frame }]);
			selection = [];
		});
		registerCommand(HuiCommands.undo, View, () -> { onUndo(); });
		registerCommand(HuiCommands.redo, View, () -> { onRedo(); });
		registerCommand(HuiCommands.selectAll, FocusedView, () -> { selection = markers; });

		gridShader = new GridShader();
		gridShader.lineColor = h3d.Vector.fromColor(GRID_COLOR);
		gridShader.stepWidth = GRID_STEP_WIDTH;
		gridShader.subdivisions = GRID_SUBDIVISIONS;
		gridShader.subAlpha = GRID_SUB_ALPHA;
		gridShader.originColor = h3d.Vector.fromColor(GRID_ORIGIN_COLOR);
		gridShader.originWidth = GRID_ORIGIN_WIDTH;

		grid.backgroundType = "hui";
		grid.huiBg.addShader(gridShader);

		buildToolbar();

		onAfterReflow = () -> {
			refresh();
		}

		rightPanel.onWheel = (e : hxd.Event) -> {
			// Keep the value under the mouse at the same screen position
			var mouse = grid.globalToLocal(rightPanel.localToGlobal(new h2d.col.Point(e.relX, e.relY)));
			var mouseX = px(mouse.x);
			var mouseY = py(mouse.y);

			var factor = Math.pow(ZOOM_SPEED, -e.wheelDelta);
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				zoom.x = hxd.Math.clamp(zoom.x * factor, MIN_ZOOM, MAX_ZOOM);
			if (useYAxis && !hxd.Key.isDown(hxd.Key.CTRL))
				zoom.y = hxd.Math.clamp(zoom.y * factor, MIN_ZOOM, MAX_ZOOM);

			pan.x = mouse.x - mouseX * grid.calculatedWidth * zoom.x;
			if (useYAxis)
				pan.y = grid.calculatedHeight - mouse.y - mouseY * grid.calculatedHeight * zoom.y;
			refresh();
		}

		grid.onPush = (e : hxd.Event) -> {
			if (e.button != 0 && e.button != 1 && e.button != 2)
				return;

			var scene = getScene();
			var originDrag = new h2d.col.Point(scene.mouseX, scene.mouseY);
			var originPan = pan.clone();
			scene.startCapture((e : hxd.Event) -> {
				switch (e.kind) {
					case ERelease, EReleaseOutside:
						scene.stopCapture();
					case EMove:
						pan.x = originPan.x + (scene.mouseX - originDrag.x);
						if (useYAxis)
							pan.y = originPan.y - (scene.mouseY - originDrag.y);
						refresh();
					default:
				}
			});
		}

		grid.onClick = (e) -> {
			switch (e.button) {
				case hxd.Key.MOUSE_LEFT:
					selection = [];
				case hxd.Key.MOUSE_RIGHT:
					var options = contextMenu();
					if (options == null || options.length == 0)
						return;
					uiBase.contextMenu(options);
				default:
			}
		}

		timerTrack.onPush = (e : hxd.Event) -> {
			if (e.button != 0 && e.button != 1 && e.button != 2)
				return;

			var scene = getScene();
			inline function setTimeFromMouse() {
				setTime(px(timerTrack.globalToLocal(new h2d.col.Point(scene.mouseX, scene.mouseY)).x));
			}

			setTimeFromMouse();
			scene.startCapture((e : hxd.Event) -> {
				switch (e.kind) {
					case ERelease, EReleaseOutside:
						scene.stopCapture();
					case EMove:
						setTimeFromMouse();
					default:
				}
			});
		}
	}

	public function refresh() {
		needRefresh = true;
	}

	public function clear(flag : ClearFlag = ClearFlag.Full) {
		if (flag.match(ClearFlag.Full) || flag.match(ClearFlag.LeftPanel)) {
			leftPanel.removeChildren();
			for (c in clips)
				c.track = null;
			tracks = [];
		}

		if (flag.match(ClearFlag.Full) || flag.match(ClearFlag.RightPanel)) {
			content.removeChildren();
			clips = [];
			markers = [];
			selection = [];
		}

		if (flag.match(ClearFlag.Full)) {
			getTime = () -> 0.;
			setTime = (_) -> {};
			isPaused = () -> false;
			setPaused = (_) -> {};
		}

		refresh();
	}

	public function getTrack(name: String) {
		for (t in tracks) {
			if (t.name == name) {
				return t;
			}
		}
		return null;
	}

	public function addTrack(name: String, e : HuiElement) {
		tracks.push({ name: name, content: e });
	}

	public function addClip(name : String, start : Int, end : Int, ?track : String) {
		var c : Clip = { name: name, start: start, end: end };
		if (track != null)
			c.track = getTrack(track);
		clips.push(c);
		refresh();
	}

	public function addMarker(name : String, frame: Int, ?track : String) {
		var m : Marker = { name: name, frame: frame };
		if (track != null)
			m.track = getTrack(track);
		markers.push(m);
		refresh();
	}

	public function removeMarker(name : String, frame: Int) {
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

	override function update(dt: Float) {
		super.update(dt);

		var t = getTime();
		var decimals = hxd.Math.imax(0, Math.ceil(-Math.log(hstep) / Math.log(10) - 1e-6));
		var f = Math.pow(10, decimals);
		time.text = '${Math.round(t * f) / f}';
		playhead.setPosition(sx(t) - (playhead.calculatedWidth / 2), (timerTrack.calculatedHeight / 2) - (head.calculatedHeight / 2));

		if (needRefresh)
			refreshInternal();
	}

	override function getViewName():String {
		return "Timeline";
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = super.getToolbarWidgets();

		var rewindBtn = new HuiButton();
		rewindBtn.dom.addClass("group-start");
		new HuiIcon(HuiRes.ui.icons.fast_rewind, rewindBtn);
		widgets.push(rewindBtn);

		var previousBtn = new HuiButton();
		previousBtn.dom.addClass("group");
		new HuiIcon(HuiRes.ui.icons.skip_previous, previousBtn);
		widgets.push(previousBtn);

		var playBtn = new HuiButton();
		playBtn.dom.addClass("group");
		var playBtnIcon = new HuiIcon(isPaused() ? HuiRes.ui.icons.play : HuiRes.ui.icons.pause, playBtn);
		widgets.push(playBtn);
		playBtn.onClick = (e) -> {
			setPaused(!isPaused());
			playBtnIcon.setIcon(isPaused() ? HuiRes.ui.icons.play : HuiRes.ui.icons.pause);
		}

		var nextBtn = new HuiButton();
		nextBtn.dom.addClass("group");
		new HuiIcon(HuiRes.ui.icons.skip_next, nextBtn);
		widgets.push(nextBtn);

		var forwardBtn = new HuiButton();
		forwardBtn.dom.addClass("group-end");
		new HuiIcon(HuiRes.ui.icons.fast_forward, forwardBtn);
		widgets.push(forwardBtn);

		return widgets;
	}

	function getStep(range : Float) : Float {
		var step = MIN_STEP;
		var i = 0;
		while (range / step > MAX_LABELS)
			step *= (i++ % 3 == 1) ? 2.5 : 2;
		return step;
	}

	function refreshInternal() {
		for (l in labels)
			l.remove();
		labels.resize(0);

		var minX = px(0);
		var maxX = px(rightPanel.calculatedWidth);

		hstep = getStep(maxX - minX);
		var minS = Math.floor(minX / hstep);
		var maxS = Math.ceil(maxX / hstep);

		for (i in minS...(maxS+1)) {
			var ix = i * hstep;

			var label = new HuiText('${hxd.Math.fmt(ix)}', timerTrack);
			label.setPosition(sx(ix) - (label.textWidth / 2), (timerTrack.calculatedHeight / 2) - (label.textHeight / 2));
			labels.push(label);
		}

		if (useYAxis) {
			var minY = py(grid.calculatedHeight);
			var maxY = py(0);

			vstep = getStep(maxY - minY);
			minS = Math.floor(minY / vstep);
			maxS = Math.ceil(maxY / vstep);

			for (i in minS...(maxS+1)) {
				var iy = i * vstep;

				var label = new HuiText('${hxd.Math.fmt(iy)}', grid);
				label.setPosition(5, sy(iy) - (label.textHeight / 2));
				labels.push(label);
			}
		}

		var h = Std.int(rightPanel.calculatedHeight - playhead.y);
		if (body.minHeight != h)
			body.minHeight = body.maxHeight = h;

		// Update Grid
		var gridOrigin = grid.localToGlobal(new h2d.col.Point(0, 0));
		gridShader.stepOrigin = new h3d.Vector(gridOrigin.x + sx(0), gridOrigin.y + sy(0), 0);
		gridShader.stepSpacing = new h3d.Vector(sx(hstep) - sx(0), sy(0) - sy(vstep), 0);
		gridShader.useYAxis = useYAxis;

		for (t in tracks) {
			if (t.element == null) {
				t.element = new HuiElement(leftPanel);
				t.element.dom.addClass("hui-track");
				t.element.addChild(t.content);
			}
		}

		for (c in clips) {
			if (c.element == null) {
				c.element = new HuiElement(content);
				c.element.dom.addClass("hui-clip");
				new HuiText(c.name, c.element);
			}

			var width = Std.int(sx(frameToTime(c.end)) - sx(frameToTime(c.start)));
			c.element.setWidth(width);

			var y = 0.;
			if (c.track != null)
				y = content.globalToLocal(c.track.element.localToGlobal(new h2d.col.Point(0, 0))).y;
			c.element.setPosition(sx(frameToTime(c.start)), y);
		}

		function placeMarker(m : Marker) {
			var y = 0.;
			if (m.track != null)
				y = content.globalToLocal(m.track.element.localToGlobal(new h2d.col.Point(0, 0))).y;
			m.element.setPosition(sx(frameToTime(m.frame)) - (m.element.calculatedWidth / 2), y);
		}

		for (m in markers) {
			if (m.element == null) {
				m.element = new HuiElement(content);
				m.element.dom.addClass("hui-marker");
				m.element.onAfterReflow = () -> placeMarker(m);
				new HuiIcon(HuiRes.ui.icons.diamond, m.element);
				var labelContainer = new HuiElement(m.element);
				labelContainer.dom.addClass("label-container");
				var label = new HuiText(m.name, labelContainer);
				var input = new HuiTextInput(m.name, null, labelContainer);
				input.text = m.name;
				input.visible = false;
				input.onFocusLost = (e : hxd.Event) -> {
					label.visible = true;
					label.text = input.text;
					input.visible = false;
					var oldMarker = Reflect.copy(m);
					m.name = input.text;
					onChange(oldMarker, Reflect.copy(m));
				}

				m.element.onPush = (e : hxd.Event) -> {
					var scene = getScene();
					var oldM = Reflect.copy(m);
					scene.startCapture((e : hxd.Event) -> {
						switch (e.kind) {
							case ERelease, EReleaseOutside:
								scene.stopCapture();
								var newM = Reflect.copy(m);
								onChange(oldM, newM);
							case EMove:
								if (m.track != null) {
									var min = 0;
									var max = 0;
									for (c in clips) {
										if (c.track == m.track) {
											min = c.start;
											max = c.end - 1;
											break;
										}
									}
									m.frame = hxd.Math.iclamp(timeToFrame(px(content.globalToLocal(new h2d.col.Point(scene.mouseX, scene.mouseY)).x)), min, max);
								}
								else {
									m.frame = hxd.Math.imax(timeToFrame(px(content.globalToLocal(new h2d.col.Point(scene.mouseX, scene.mouseY)).x)), 0);
								}
							default:
						}
					});

					e.propagate = false;
				}

				m.element.onClick = (e : hxd.Event) -> {
					if (hxd.Key.isDown(hxd.Key.CTRL) || hxd.Key.isDown(hxd.Key.SHIFT)) {
						if (selection.contains(m))
							selection.remove(m);
						else
							selection.push(m);
					}
					else
						selection = [m];

					e.propagate = false;
				}

				m.element.onDoubleClick = (e : hxd.Event) -> {
					label.visible = false;
					input.visible = true;
					input.focus();
				}
			}

			m.element.dom.toggleClass("selected", selection.contains(m));
			placeMarker(m);
		}

		needRefresh = false;
	}

	public dynamic function contextMenu() : Array<hrt.ui.HuiMenu.MenuItem> { return []; };
	public dynamic function getTime() : Float { return 0.; };
	public dynamic function setTime(t : Float) {};
	public dynamic function isPaused() : Bool { return false; };
	public dynamic function setPaused(v : Bool) {};

	public dynamic function onSave() { };
	public dynamic function onDelete(markers : Array<Marker>) { };
	public dynamic function onChange(oldMarker : Marker, newMarker : Marker) { };
	public dynamic function onUndo() { };
	public dynamic function onRedo() { };

	static var _ = HuiView.register("timeline", Timeline);
}