package hide.view;
import hrt.ui.*;

class GridShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			var position : Vec2;
		}

		@param var lineColor : Vec3;
		@param var lineWidth : Float;
		@param var lineSpacing : Float;

		@param var pan : Vec2;
		@param var zoom : Vec2;

		var absolutePosition : Vec4;
		var pixelColor : Vec4;

		function grid(position : Vec2, lineWidth : Float, idx : Int) : Float {
			var deriv = fwidth(position);
			var drawWidth = clamp(vec2(lineWidth, lineWidth), deriv, vec2(0.5, 0.5));
			var lineAA = max(deriv, vec2(0.0001, 0.0001)) * 1.5;
			var gridUV = abs(fract(position) * 2.0 - 1.0);
			var grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, 1.0 - gridUV);
			grid2 *= saturate(vec2(lineWidth, lineWidth) / drawWidth);
			grid2 = mix(grid2, vec2(lineWidth, lineWidth), saturate(deriv * 2.0 - 1.0));
			return max(grid2.x, grid2.y);
		}

		function fragment() {
			pixelColor.rgb = lineColor;
			pixelColor.a = 0;
			for (idx in 0...2) {
				var f = pow(10., float(idx));
				pixelColor.a = max(pixelColor.a, grid(
					absolutePosition.xy * (1 / (lineSpacing * f)) / zoom,
					lineWidth,
					idx));
			}
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
	static final GRID_WIDTH = 0.01;
	static final GRID_LINESPACING = 100;
	static final GRID_ORIGIN_COLOR = 0x7E7E7E;
	static final GRID_ORIGIN_WIDTH = 2;
	static final MIN_ZOOM = 0.1;
	static final MAX_ZOOM = 2;

	var labels = [];

	// Edition
	var gridShader : GridShader = null;
	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);
	var onPanDrag : (e : hxd.Event) -> Void;

	inline function sx(px : Float) { return px * calculatedWidth * zoom.x + pan.x; }
	inline function sy(py : Float) { return calculatedHeight - (py * calculatedHeight * zoom.y + pan.y); }
	inline function px(sx : Float) { return (sx - pan.x) / (calculatedWidth * zoom.x); }
	inline function py(sy : Float) { return (calculatedHeight - sy - pan.y) / (calculatedHeight * zoom.y); }

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		gridShader = new GridShader();
		gridShader.lineColor = h3d.Vector.fromColor(GRID_COLOR);
		gridShader.lineWidth = GRID_WIDTH;
		gridShader.lineSpacing = GRID_LINESPACING;
		gridShader.zoom = new h3d.Vector(1, 1, 0);
		gridShader.pan = new h3d.Vector(0, 0, 0);

		grid.backgroundType = "hui";
		grid.huiBg.addShader(gridShader);

		buildToolbar();

		onAfterReflow = () -> {
			// refresh();
		}

		rightPanel.onWheel = (e : hxd.Event) -> {
			var amount = e.wheelDelta * -0.05;
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				zoom.x = hxd.Math.clamp(zoom.x + amount, MIN_ZOOM, MAX_ZOOM);
			if (!hxd.Key.isDown(hxd.Key.CTRL))
				zoom.y = hxd.Math.clamp(zoom.y + amount, MIN_ZOOM, MAX_ZOOM);
			refresh();
		}

		rightPanel.onPush = (e : hxd.Event) -> {
			if (onPanDrag != null)
				return;

			if (e.button == 0 || e.button == 1 || e.button == 2) {
				var originDrag = new h2d.col.Point(e.relX, e.relY);
				var originPan = pan.clone();
				onPanDrag = (e) -> {
					pan.x = originPan.x + (e.relX - originDrag.x);
					pan.y = originPan.y - (e.relY - originDrag.y);
					refresh();
				}
			}
		}

		rightPanel.onMove = (e : hxd.Event) -> {
			if (onPanDrag != null)
				onPanDrag(e);
		}

		rightPanel.onRelease = (e : hxd.Event) -> {
			onPanDrag = null;
		}

		refresh();
	}

	public function refresh() {
		for (l in labels)
			l.remove();
		labels.resize(0);

		var minX = Math.floor(px(0));
		var maxX = Math.ceil(px(rightPanel.calculatedWidth));

		var hstep = 0.1;
		while((maxX - minX) / hstep > 21)
			hstep *= 2;
		var minS = Math.floor(minX / hstep);
		var maxS = Math.ceil(maxX / hstep);

		for (i in minS...(maxS+1)) {
			var ix = i * hstep;

			var label = new HuiText('${hxd.Math.fmt(ix)}', timerTrack);
			label.setPosition(sx(ix), (timerTrack.calculatedHeight / 2) - (label.textHeight / 2));
			labels.push(label);
		}
	}

	public dynamic function getTime() : Float { return 0.; };
	public dynamic function onPause() {};
	public dynamic function onPlay() {};

	override function update(dt: Float) {
		super.update(dt);

		var t = getTime();
		time.text = '${hxd.Math.round(t * 10) / 10}';
		playhead.setPosition(sx(t), (timerTrack.calculatedHeight / 2) - (playhead.calculatedHeight / 2));

		// if (scene != null)
		// 	setTime(@:privateAccess scene.renderer.ctx.time);
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
		new HuiIcon(HuiRes.ui.icons.play, playBtn);
		widgets.push(playBtn);
		playBtn.onClick = (e) -> {
			// isPaused = !isPaused;
			// if (isPaused)
			// 	onPause();
			// else
			// 	onPlay();
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

	static var _ = HuiView.register("timeline", Timeline);
}