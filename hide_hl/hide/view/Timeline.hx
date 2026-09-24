package hide.view;
import hrt.ui.*;

class GridShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			var position : Vec2;
		}

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
				stepLines(absolutePosition.y, stepOrigin.y, stepSpacing.y));

			var subSpacing = stepSpacing / subdivisions;
			var subFade = saturate((subSpacing - 4.0) / 4.0);
			var minor = max(
				stepLines(absolutePosition.x, stepOrigin.x, subSpacing.x) * subFade.x,
				stepLines(absolutePosition.y, stepOrigin.y, subSpacing.y) * subFade.y);

			var origin = max(
				lineMask(abs(absolutePosition.x - stepOrigin.x), originWidth),
				lineMask(abs(absolutePosition.y - stepOrigin.y), originWidth));

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
						<hui-element id="event-track"></hui-element>
						<hui-element id="grid"></hui-element>
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
	static final GRID_STEP_WIDTH = 1;
	static final GRID_SUBDIVISIONS = 5;
	static final GRID_SUB_ALPHA = 0.35;
	static final GRID_ORIGIN_COLOR = 0x7E7E7E;
	static final GRID_ORIGIN_WIDTH = 2;
	static final MIN_STEP = 1e-2;
	static final MAX_LABELS = 21;
	static final ZOOM_SPEED = 1.1;
	static final MIN_ZOOM = 1e-4;
	static final MAX_ZOOM = 1e4;

	var gridShader : GridShader = null;
	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);
	var onPanDrag : (e : hxd.Event) -> Void;
	var labels = [];
	var needRefresh = true;
	var hstep = MIN_STEP;
	var vstep = MIN_STEP;

	inline function sx(px : Float) { return px * calculatedWidth * zoom.x + pan.x; }
	inline function sy(py : Float) { return grid.calculatedHeight - (py * grid.calculatedHeight * zoom.y + pan.y); }
	inline function px(sx : Float) { return (sx - pan.x) / (calculatedWidth * zoom.x); }
	inline function py(sy : Float) { return (grid.calculatedHeight - sy - pan.y) / (grid.calculatedHeight * zoom.y); }

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

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
			if (!hxd.Key.isDown(hxd.Key.CTRL))
				zoom.y = hxd.Math.clamp(zoom.y * factor, MIN_ZOOM, MAX_ZOOM);

			pan.x = mouse.x - mouseX * calculatedWidth * zoom.x;
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
						pan.y = originPan.y - (scene.mouseY - originDrag.y);
						refresh();
					default:
				}
			});
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

	public dynamic function getTime() : Float { return 0.; };
	public dynamic function setTime(t : Float) {};
	public dynamic function isPaused() : Bool { return false; };
	public dynamic function setPaused(v : Bool) {};

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

	override function getContextMenuContent(content:Array<hrt.ui.HuiMenu.MenuItem>) {
		// content.push({label: "Refresh", click: () -> fileBrowser.markRefresh()});
		// content.push({label: "Layout", menu: [
		// 		{label: "File Tree", click: updateMode.bind(FileTree)},
		// 		{label: "Galery", click: updateMode.bind(Gallery)},
		// 		{label: "Horizontal", click: updateMode.bind(Horizontal)},
		// 		{label: "Vertical", click: updateMode.bind(Vertical)},
		// 	]
		// });
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

		var h = Std.int(rightPanel.calculatedHeight - playhead.y);
		if (body.minHeight != h)
			body.minHeight = body.maxHeight = h;

		// Update Grid
		var gridOrigin = grid.localToGlobal(new h2d.col.Point(0, 0));
		gridShader.stepOrigin = new h3d.Vector(gridOrigin.x + sx(0), gridOrigin.y + sy(0), 0);
		gridShader.stepSpacing = new h3d.Vector(sx(hstep) - sx(0), sy(0) - sy(vstep), 0);

		needRefresh = false;
	}

	static var _ = HuiView.register("timeline", Timeline);
}