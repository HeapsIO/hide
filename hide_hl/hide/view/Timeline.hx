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

		function grid(position : Vec2, lineWidth: Float, idx : Int) : Float {
			var gridUV = abs(fract(position) * 2.0 - 1.0);
			var lineX = smoothstep(1.0 - lineWidth, 1.0, gridUV.x);
			var lineY = smoothstep(1.0 - lineWidth, 1.0, gridUV.y);
			return max(lineX, lineY);
		}

		function fragment() {
			pixelColor.rgb = lineColor;
			pixelColor.a = max(pixelColor.a, grid(
				absolutePosition.xy * (1 / lineSpacing) / zoom,
				lineWidth,
				0));
		}
	}
}

class Timeline extends HuiView<{path: String, mode: hrt.ui.HuiFileBrowser.BrowserMode}> {
	static var SRC =
		<timeline>
			<hui-split-container id="container" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal} anchor-to={hrt.ui.HuiSplitContainer.AnchorTo.End} save-display-key="timeline-panel-split">
				<hui-element id="left-panel"></hui-element>
				<hui-element id="right-panel">
					<hui-element id="timer-track"></hui-element>
					<hui-element id="event-track"></hui-element>
					<hui-element id="grid"></hui-element>
					<hui-element id="playhead">
						<hui-element id="head">
							<hui-text("0.4") id="time"/>
						</hui-element>
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

	var gridGraphics : h2d.Graphics;
	var gridLabels = [];

	var gridShader : GridShader = null;
	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);

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
			var amount = e.wheelDelta * -0.1;
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				gridShader.zoom.x = hxd.Math.clamp(gridShader.zoom.x + amount, MIN_ZOOM, MAX_ZOOM);
			if (!hxd.Key.isDown(hxd.Key.CTRL))
				gridShader.zoom.y = hxd.Math.clamp(gridShader.zoom.y + amount, MIN_ZOOM, MAX_ZOOM);
			refresh();
		}
	}

	override function getViewName():String {
		return "Timeline";
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = super.getToolbarWidgets();

		var rewindBtn = new HuiButton();
		rewindBtn.dom.addClass("group-start");
		new HuiIcon("fast_rewind", rewindBtn);
		widgets.push(rewindBtn);

		var previousBtn = new HuiButton();
		previousBtn.dom.addClass("group");
		new HuiIcon("skip_previous", previousBtn);
		widgets.push(previousBtn);

		var playBtn = new HuiButton();
		playBtn.dom.addClass("group");
		new HuiIcon("play", playBtn);
		widgets.push(playBtn);

		var nextBtn = new HuiButton();
		nextBtn.dom.addClass("group");
		new HuiIcon("skip_next", nextBtn);
		widgets.push(nextBtn);

		var forwardBtn = new HuiButton();
		forwardBtn.dom.addClass("group-end");
		new HuiIcon("fast_forward", forwardBtn);
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

	function refresh() {
		if (gridGraphics == null)
			gridGraphics = new h2d.Graphics(grid);

		for (l in gridLabels) l.remove();
		gridLabels = [];
		gridGraphics.clear();
		gridGraphics.setPosition(0, 0);

		// Grid columns
		var min = Math.floor(px(0));
		var max = Math.ceil(px(calculatedWidth));
		var step = Math.floor((0.1 * (1 / zoom.x) * 20)) / 20;
		var minS = Math.floor(min / step);
		var maxS = Math.ceil(max / step);
		for (i in minS...(maxS+1)) {
			var ix = i * step;

			gridGraphics.lineStyle(ix == 0 ? GRID_ORIGIN_WIDTH : GRID_WIDTH, ix == 0 ? GRID_ORIGIN_COLOR : GRID_COLOR, 1);

			gridGraphics.moveTo(sx(ix), 0);
			gridGraphics.lineTo(sx(ix), calculatedHeight);

			// var l = new HuiText(""+hxd.Math.fmt(ix), this);
			// l.setPosition(sx(ix) + 5, calculatedHeight - 18);
			// gridLabels.push(l);
		}

		// Grid lines
		var min = Math.floor(py(calculatedHeight));
		var max = Math.ceil(py(0));
		step = Math.floor((0.1 * (1 / zoom.y) * 20)) / 20;
		minS = Math.floor(min / step);
		maxS = Math.ceil(max / step);
		for (i in minS...(maxS+1)) {
			var iy = i * step;

			gridGraphics.lineStyle(iy == 0 ? GRID_ORIGIN_WIDTH : GRID_WIDTH, iy == 0 ? GRID_ORIGIN_COLOR : GRID_COLOR, 1);

			gridGraphics.moveTo(0, sy(iy));
			gridGraphics.lineTo(calculatedWidth, sy(iy));

			// var l = new HuiText(""+hxd.Math.fmt(iy), this);
			// l.setPosition(0, sy(iy) - 18);
			// gridLabels.push(l);
		}
	}

	static var _ = HuiView.register("timeline", Timeline);
}