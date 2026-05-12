package hrt.ui;

#if hui
@:access(hrt.prefab.Curve)
class HuiCurveBox extends HuiElement {
	static var SRC = <hui-curve-box>
	</hui-curve-box>

	public static var CURVE_COLOR = 0x05f505;
	public static var CURVE_WIDTH = 1;
	public static var CURVE_PRECISION = 50;

	public var value : hrt.prefab.Curve;

	var root : h2d.Object;
	var graphics : h2d.Graphics;
	var editor : HuiCurveEditor = null;
	var editorGuard : Int = 0;
	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		root = new h2d.Object(this);
		this.getProperties(root).isAbsolute = true;

		this.onClick = (e : hxd.Event) -> {
			if (editor == null) {
				editor = new HuiCurveEditor(this, null);
				editor.value = this.value;
				uiBase.addPopup(editor, { object: Element(this), directionX: StartInside, directionY: EndOutside });

				editor.onCloseListeners.push(() -> { editor.remove(); editor = null; });
				editor.onValueChanged = (isTemporary) -> {
					editorGuard++;
					editorGuard--;
					onValueChanged(isTemporary);
				};
			}
			else {
				editor.close();
			}
		};

		// Debug
		// value = hxd.res.Loader.currentInstance.load("prefabs/simple.prefab").toPrefab().load().getOpt(hrt.prefab.Curve);
	}

	override function onAfterReflow() {
		updatePreview();
	}

	function updatePreview() {
		if (this.graphics == null)
			graphics = new h2d.Graphics(root);

		graphics.setPosition(0, this.calculatedHeight);
		graphics.clear();

		if (value == null)
			return;

		graphics.lineStyle(CURVE_WIDTH, CURVE_COLOR, 1);

		graphics.moveTo(0, 0);
		for (idx => v in value.sample(CURVE_PRECISION))
			graphics.lineTo((idx / CURVE_PRECISION) * this.calculatedWidth, (v / value.maxValue) * -1 * this.calculatedHeight);
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}

class HuiCurveEditor extends HuiPopup {
	static var SRC = <hui-curve-editor>
	</hui-curve-editor>

	public static var GRID_COLOR = 0x5A5A5A;
	public static var GRID_WIDTH = 1;
	public static var GRID_ORIGIN_COLOR = 0x7E7E7E;
	public static var GRID_ORIGIN_WIDTH = 2;
	public static var CURVE_COLOR = 0x05f505;
	public static var CURVE_WIDTH = 1;
	public static var CURVE_PRECISION = 500;
	public static var MIN_ZOOM = 0.1;
	public static var MAX_ZOOM = 2;

	public var value : hrt.prefab.Curve = null;

	var root : h2d.Object;
	var gridGraphics : h2d.Graphics;
	var gridLabels = [];
	var curveGraphics : h2d.Graphics;

	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);

	public function new (b : HuiCurveBox, ?parent) {
		super(parent);
		initComponent();

		root = new h2d.Object(this);
		this.getProperties(root).isAbsolute = true;

		onWheel = (e : hxd.Event) -> {
			var amount = e.wheelDelta * -0.1;
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				zoom.x = hxd.Math.clamp(zoom.x + amount, MIN_ZOOM, MAX_ZOOM);
			if (!hxd.Key.isDown(hxd.Key.CTRL))
				zoom.y = hxd.Math.clamp(zoom.y + amount, MIN_ZOOM, MAX_ZOOM);
			refresh();
		}

		var originDrag = null;
		var originPan = null;
		onRelease = (e : hxd.Event) -> {
			if (e.keyCode != 0 || e.button != hxd.Key.MOUSE_MIDDLE)
				return;
			originDrag = null;
			originPan = null;
		}

		onMove = (e : hxd.Event) -> {
			if (!hxd.Key.isDown(hxd.Key.MOUSE_MIDDLE))
				return;

			if (originDrag == null) {
				originDrag = new h2d.col.Point(e.relX, e.relY);
				originPan = pan.clone();
			}

			var dx = e.relX - originDrag.x;
			pan.x = originPan.x - (dx / calculatedWidth);
			var dy = e.relY - originDrag.y;
			pan.y = originPan.y + (dy / calculatedHeight);
			refresh();
		}

		onAfterReflow = () -> {
			updateAnchor(true);
			refresh();
		}
	}

	public function refreshGrid() {
		if (gridGraphics == null)
			gridGraphics = new h2d.Graphics(root);

		for (l in gridLabels) l.remove();
		gridLabels = [];
		gridGraphics.clear();
		gridGraphics.setPosition(0, this.calculatedHeight);

		// Grid columns
		var min = Math.floor(px(0));
		var max = Math.ceil(px(calculatedWidth));
		var step = 0.1;
		var minS = Math.floor(min / step);
		var maxS = Math.ceil(max / step);
		for (i in minS...(maxS+1)) {
			var ix = i * step;

			gridGraphics.lineStyle(ix == 0 ? GRID_ORIGIN_WIDTH : GRID_WIDTH, ix == 0 ? GRID_ORIGIN_COLOR : GRID_COLOR, 1);

			gridGraphics.moveTo(sx(ix), 0);
			gridGraphics.lineTo(sx(ix), -calculatedHeight);

			var l = new HuiText(""+hxd.Math.fmt(ix), gridGraphics);
			l.setPosition(sx(ix) + 5, -18);
			gridLabels.push(l);
		}

		// Grid lines
		min = Math.floor(py(0));
		max = Math.ceil(py(-calculatedHeight));
		step = 0.1;
		minS = Math.floor(min / step);
		maxS = Math.ceil(max / step);
		for (i in minS...(maxS+1)) {
			var iy = i * step;

			gridGraphics.lineStyle(iy == 0 ? GRID_ORIGIN_WIDTH : GRID_WIDTH, iy == 0 ? GRID_ORIGIN_COLOR : GRID_COLOR, 1);

			gridGraphics.moveTo(0, sy(iy));
			gridGraphics.lineTo(calculatedWidth, sy(iy));

			var l = new HuiText(""+hxd.Math.fmt(iy), gridGraphics);
			l.setPosition(0, sy(iy) - 18);
			gridLabels.push(l);
		}
	}

	public function refreshCurve() {
		if (curveGraphics == null)
			curveGraphics = new h2d.Graphics(root);

		curveGraphics.setPosition(0, this.calculatedHeight);
		curveGraphics.clear();

		if (value == null)
			return;

		curveGraphics.lineStyle(CURVE_WIDTH, CURVE_COLOR, 1);

		curveGraphics.moveTo(0, 0);
		for (idx in 0...CURVE_PRECISION) {
			var x = px((idx / CURVE_PRECISION) * calculatedWidth);
			var y = value.getVal(x);
			curveGraphics.lineTo(sx(x), sy(y));
		}
	}

	public function refresh() {
		refreshGrid();
		refreshCurve();
	}

	inline function sx(px : Float) { return Math.round((px - pan.x) * calculatedWidth); }
	inline function sy(py : Float) { return Math.round((-py + pan.y) * calculatedHeight); }
	inline function px(sx : Float) { return (sx / calculatedWidth) + pan.x; }
	inline function py(sy : Float) { return (-sy / calculatedHeight) + pan.y; }

	public dynamic function onValueChanged(isTemporary: Bool) {}
}
#end