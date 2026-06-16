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
	public function new(?value : hrt.prefab.Curve, ?parent: h2d.Object) {
		super(parent);
		this.value = value;

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
					this.value = editor.value;
					onValueChanged(isTemporary);
				};
			}
			else {
				editor.close();
			}
		};
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

	static public var deleteKeyCmd = new hrt.ui.HuiCommands.HuiCommand("Delete Key", {key: hxd.Key.DELETE});
	static public var focusCmd = new hrt.ui.HuiCommands.HuiCommand("Focus", {key: hxd.Key.F});

	public var value : hrt.prefab.Curve = null;

	var huiCurveBox : HuiCurveBox = null;
	var zoom = new h2d.col.Point(1, 1);
	var pan = new h2d.col.Point(0, 0);
	var selection : Array<Int> = null;
	var selectionRectangle : HuiElement;
	var selectionBounds : HuiElement;
	var onDrag : (e : hxd.Event) -> Void;
	var onDragFinished : (e : hxd.Event) -> Void;

	var root : h2d.Object;
	var gridGraphics : h2d.Graphics;
	var gridLabels = [];
	var curveGraphics : h2d.Graphics;
	var keysBitmaps = [];
	var draggedKey = -1;

	inline function sx(px : Float) { return px * calculatedWidth * zoom.x + pan.x; }
	inline function sy(py : Float) { return calculatedHeight - (py * calculatedHeight * zoom.y + pan.y); }
	inline function px(sx : Float) { return (sx - pan.x) / (calculatedWidth * zoom.x); }
	inline function py(sy : Float) { return (calculatedHeight - sy - pan.y) / (calculatedHeight * zoom.y); }

	public function new (b : HuiCurveBox, ?parent) {
		super(parent);
		initComponent();

		registerCommand(deleteKeyCmd, ElementAndChildren, () -> delete(selection));
		registerCommand(focusCmd, ElementAndChildren, focus);

		root = new h2d.Object(this);
		this.getProperties(root).isAbsolute = true;

		selectionBounds = new HuiElement(this);
		selectionBounds.dom.addClass("selection-bounds");
		selectionRectangle = new HuiElement(this);
		selectionRectangle.dom.addClass("selection-rectangle");

		onPush = (e : hxd.Event) -> {
			if (onDrag != null)
				return;

			if (hxd.Key.isDown(hxd.Key.MOUSE_MIDDLE)) {
				var originDrag = new h2d.col.Point(e.relX, e.relY);
				var originPan = pan.clone();
				onDrag = (e) -> {
					var dx = e.relX - originDrag.x;
					pan.x = originPan.x + dx;
					var dy = e.relY - originDrag.y;
					pan.y = originPan.y - dy;
					refresh();
				}
			}
			else {
				var start = new h2d.col.Point(e.relX, e.relY);
				onDrag = (e) -> {
					var end = new h2d.col.Point(e.relX, e.relY);
					var b = new h2d.col.Bounds();
					b.addPoint(start);
					b.addPoint(end);

					this.selectionRectangle.setPosition(b.xMin, b.yMin);
					this.selectionRectangle.setWidth(Std.int(b.width));
					this.selectionRectangle.setHeight(Std.int(b.height));

					if (value != null) {
						var s = [];
						for (idx => k in value.keys ?? []) {
							if (b.contains(new h2d.col.Point(sx(k.time), sy(k.value))))
								s.push(idx);
						}
						select(s);
					}
				}

				onDragFinished = (e) -> {
					selectionRectangle.setWidth(0);
					selectionRectangle.setHeight(0);
				}
			}
		}

		onRelease = (e : hxd.Event) -> {
			if (onDragFinished != null)
				onDragFinished(e);
			onDrag = null;
			onDragFinished = null;
		}

		onMove = (e : hxd.Event) -> {
			if (onDrag != null)
				onDrag(e);
		}

		onWheel = (e : hxd.Event) -> {
			var amount = e.wheelDelta * -0.1;
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				zoom.x = hxd.Math.clamp(zoom.x + amount, MIN_ZOOM, MAX_ZOOM);
			if (!hxd.Key.isDown(hxd.Key.CTRL))
				zoom.y = hxd.Math.clamp(zoom.y + amount, MIN_ZOOM, MAX_ZOOM);
			refresh();
		}

		onClick = (e : hxd.Event) -> {
			if (hxd.Key.isDown(hxd.Key.CTRL) && e.keyCode == hxd.Key.MOUSE_LEFT) {
				addKey(px(e.relX), py(e.relY));
				refresh();
			}

			select(null);
		}

		onAfterReflow = () -> {
			updateAnchor(true);
			refresh();
		}
	}

	public function refresh() {
		refreshGrid();
		refreshCurve();
		refreshKeys();
	}

	public function refreshGrid() {
		if (gridGraphics == null)
			gridGraphics = new h2d.Graphics(root);

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

			var l = new HuiText(""+hxd.Math.fmt(ix), this);
			l.setPosition(sx(ix) + 5, calculatedHeight - 18);
			gridLabels.push(l);
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

			var l = new HuiText(""+hxd.Math.fmt(iy), this);
			l.setPosition(0, sy(iy) - 18);
			gridLabels.push(l);
		}
	}

	public function refreshCurve() {
		if (curveGraphics == null)
			curveGraphics = new h2d.Graphics(root);

		curveGraphics.setPosition(0, 0);
		curveGraphics.clear();

		if (value == null)
			return;

		curveGraphics.lineStyle(CURVE_WIDTH, CURVE_COLOR, 1);

		curveGraphics.moveTo(0, 0);
		for (idx in 0...CURVE_PRECISION) {
			var x = px((idx / CURVE_PRECISION) * calculatedWidth);
			var y = value.getVal(x);
			curveGraphics.lineTo(sx(x), sy(value.getVal(x)));
		}
	}

	public function refreshKeys() {
		if (value == null)
			return;

		selectionBounds.setHeight(0);
		selectionBounds.setWidth(0);

		if (value.keys.length != keysBitmaps.length) {
			for (k in keysBitmaps)
				k.remove();
			keysBitmaps = [];
			for (idx => k in value.keys) {
				var bmp = new HuiIcon("diamond", this);
				bmp.alpha = 0.5;
				keysBitmaps.push(bmp);
				bmp.onPush = (e) -> {
					if (e.keyCode == hxd.Key.MOUSE_LEFT) {
						onDrag = (e) -> {
							var x = px(e.relX);
							var y = py(e.relY);
							value.keys[idx].time = x;
							value.keys[idx].value = y;
						}
					}
				}

				bmp.onRelease = (e) -> {
					if (onDragFinished != null)
						onDragFinished(e);
					onDrag = null;
					onDragFinished = null;
				}

				bmp.onClick = (e) -> {
					if (hxd.Key.isDown(hxd.Key.CTRL)) {
						if (!selection.contains(idx))
							selection.push(idx);
						select(selection);
					}
					else {
						select([idx]);
					}
				}
			}
		}

		var iconSize = 20;
		var b = new h2d.col.Bounds();
		for (idx => k in value.keys) {
			keysBitmaps[idx].setPosition(sx(k.time) - (iconSize / 2), sy(k.value) - (iconSize / 2));
			b.addPoint(new h2d.col.Point(k.time, k.value));
		}

		selectionBounds.setPosition(sx(b.xMin), sy(b.yMin));
		selectionBounds.setWidth(Std.int(b.width * calculatedWidth));
		selectionBounds.setHeight(Std.int(b.height * calculatedHeight));
	}

	function focus() {
		if (value == null)
			return;

		var bounds = value.getBounds();
		if (bounds.width <= 0) {
			bounds.xMin = 0.0;
			bounds.xMax = 1.0;
		}

		if (bounds.height <= 0) {
			bounds.yMin = -1.0;
			bounds.yMax = 1.0;
		}

		pan.x = bounds.xMin;
		pan.y = bounds.yMin;
		zoom.x = hxd.Math.clamp(1 / (bounds.width * 1.1), MIN_ZOOM, MAX_ZOOM);
		zoom.y = hxd.Math.clamp(1 / (bounds.height * 1.1), MIN_ZOOM, MAX_ZOOM);
		refresh();
	}

	function select(keys : Array<Int>) {
		if (selection != null)
			for (s in selection)
				keysBitmaps[s].alpha = 0.5;

		selection = keys;

		if (selection != null)
			for (s in selection)
				keysBitmaps[s].alpha = 1;
	}

	function delete(keys : Array<Int>) {
		if (keys == null)
			return;

		for (k in keys)
			value.keys.remove(value.keys[k]);
	}

	function addKey(px : Float, py : Float) {
		if (value == null)
			value = new hrt.prefab.Curve(null, null);

		value.addKey(px, py);
		onValueChanged(false);
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}
#end