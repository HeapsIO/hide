package hrt.ui;

#if hui

class HuiKeyPopup extends HuiPopup {
	static var SRC =
		<hui-key-popup class="vertical">
			<hui-element class="horizontal">
				<hui-text("Time") class="label"/>
				<hui-input-box class="value" id="time-input"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("Value") class="label"/>
				<hui-input-box class="value" id="value-input"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("Mode") class="label"/>
				<hui-select class="value" id="mode-select"/>
			</hui-element>
		</hui-key-popup>

	public function new(k : hrt.prefab.Curve.CurveKey, editor : HuiCurveEditor, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		function onChange() {
			k.time = Std.parseFloat(timeInput.text);
			k.value = Std.parseFloat(valueInput.text);
			k.mode = modeSelect.value;
			@:privateAccess editor.fixKey(editor.value.keys.indexOf(k));
		}

		modeSelect.items = [
			{ label: "Aligned", value: 0},
			{ label: "Free", value: 1},
			{ label: "Linear", value: 2},
			{ label: "Constant", value: 3}
		];
		modeSelect.value = k.mode;

		timeInput.text = '${k.time}';
		valueInput.text = '${k.value}';

		timeInput.onChange = valueInput.onChange = (isTemp) -> {
			if (isTemp) return;
			onChange();
		}
	}
}
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
	public static var TAN_COLOR = 0x757575;
	public static var TAN_WIDTH = 1;
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
	var keysBitmaps : Array<{ bmp: HuiIcon, prevHandleBmp: HuiIcon, nextHandleBmp: HuiIcon, g : h2d.Graphics }> = [];
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

		onRelease = (e : hxd.Event) -> {
			if (e.button == hxd.Key.MOUSE_LEFT || e.button == hxd.Key.MOUSE_MIDDLE) {
				if (onDrag == null)
					select(null);
				if (onDragFinished != null)
					onDragFinished(e);
				onDrag = null;
				onDragFinished = null;
			}
		}

		onMove = (e : hxd.Event) -> {
			if (onDrag != null)
				onDrag(e);

			if (hxd.Key.isDown(hxd.Key.MOUSE_MIDDLE) && onDrag == null) {
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

			if (hxd.Key.isDown(hxd.Key.MOUSE_LEFT) && onDrag == null) {
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

				if (onDragFinished == null) {
					onDragFinished = (e) -> {
						selectionRectangle.setWidth(0);
						selectionRectangle.setHeight(0);
					}
				}
			}
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
			for (k in keysBitmaps) {
				k.bmp.remove();
				k.prevHandleBmp?.remove();
				k.nextHandleBmp?.remove();
			}
			keysBitmaps = [];
			for (idx => k in value.keys) {
				var bmp = new HuiIcon("diamond", this);
				bmp.alpha = 0.5;

				var g = new h2d.Graphics(this);
				g.lineStyle(1, 333333, 1);

				var prevHandleBmp = null;
				if (k.nextHandle != null) {
					prevHandleBmp = new HuiIcon("diamond", this);
					prevHandleBmp.alpha = 0.5;

					prevHandleBmp.onPush = (e) -> {
						if (e.keyCode == hxd.Key.MOUSE_LEFT) {
							onDrag = (e) -> {
								var x = px(e.relX);
								var y = py(e.relY);
								value.keys[idx].prevHandle.dt = x - value.keys[idx].time;
								value.keys[idx].prevHandle.dv = y - value.keys[idx].value;

								if (k.mode == Aligned) {
									var len = hxd.Math.distance(value.keys[idx].prevHandle.dt, value.keys[idx].prevHandle.dv);
									var otherLen = hxd.Math.distance(value.keys[idx].nextHandle.dt, value.keys[idx].nextHandle.dv);

									value.keys[idx].nextHandle.dt = (value.keys[idx].prevHandle.dt / len) * -otherLen;
									value.keys[idx].nextHandle.dv = (value.keys[idx].prevHandle.dv / len) * -otherLen;
								}

								fixKey(idx);
							}
						}
					}

					prevHandleBmp.onRelease = (e) -> {
						if (onDragFinished != null)
							onDragFinished(e);
						onDrag = null;
						onDragFinished = null;
					}
				}

				var nextHandleBmp = null;
				if (k.prevHandle != null) {
					nextHandleBmp = new HuiIcon("diamond", this);
					nextHandleBmp.alpha = 0.5;

					nextHandleBmp.onPush = (e) -> {
						if (e.keyCode == hxd.Key.MOUSE_LEFT) {
							onDrag = (e) -> {
								var x = px(e.relX);
								var y = py(e.relY);
								value.keys[idx].nextHandle.dt = x - value.keys[idx].time;
								value.keys[idx].nextHandle.dv = y - value.keys[idx].value;

								if (k.mode == Aligned) {
									var len = hxd.Math.distance(value.keys[idx].nextHandle.dt, value.keys[idx].nextHandle.dv);
									var otherLen = hxd.Math.distance(value.keys[idx].prevHandle.dt, value.keys[idx].prevHandle.dv);

									value.keys[idx].prevHandle.dt = (value.keys[idx].nextHandle.dt / len) * -otherLen;
									value.keys[idx].prevHandle.dv = (value.keys[idx].nextHandle.dv / len) * -otherLen;
								}
								
								fixKey(idx);
							}
						}
					}

					nextHandleBmp.onRelease = (e) -> {
						if (onDragFinished != null)
							onDragFinished(e);
						onDrag = null;
						onDragFinished = null;
					}
				}

				keysBitmaps.push({ bmp: bmp, prevHandleBmp: prevHandleBmp, nextHandleBmp: nextHandleBmp, g: g });

				bmp.onPush = (e) -> {
					if (e.keyCode == hxd.Key.MOUSE_LEFT) {
						onDrag = (e) -> {
							var x = px(e.relX);
							var y = py(e.relY);
							value.keys[idx].time = x;
							value.keys[idx].value = y;
							fixKey(idx);
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

					if (e.button == hxd.Key.MOUSE_RIGHT) {
						uiBase.addPopup(new HuiKeyPopup(value.keys[idx], this), { object: Element(bmp), directionX: StartInside, directionY: EndOutside });
					}
				}
			}
		}

		var iconSize = 20;
		var b = new h2d.col.Bounds();
		for (idx => k in value.keys) {
			var bitmap = keysBitmaps[idx];
			bitmap.bmp.setPosition(sx(k.time) - (iconSize / 2), sy(k.value) - (iconSize / 2));
			bitmap.g.clear();
			bitmap.g.lineStyle(TAN_WIDTH, TAN_COLOR, 1);
			if (bitmap.prevHandleBmp != null) {
				bitmap.prevHandleBmp.setPosition(sx(k.time + k.prevHandle.dt) - (iconSize / 2), sy(k.value + k.prevHandle.dv) - (iconSize / 2));
				bitmap.g.moveTo(sx(k.time), sy(k.value));
				bitmap.g.lineTo(bitmap.prevHandleBmp.x + (iconSize / 2), bitmap.prevHandleBmp.y + (iconSize / 2));
			}
			if (bitmap.nextHandleBmp != null) {
				bitmap.nextHandleBmp.setPosition(sx(k.time + k.nextHandle.dt) - (iconSize / 2), sy(k.value + k.nextHandle.dv) - (iconSize / 2));
				bitmap.g.moveTo(sx(k.time), sy(k.value));
				bitmap.g.lineTo(bitmap.nextHandleBmp.x + (iconSize / 2), bitmap.nextHandleBmp.y + (iconSize / 2));
			}

			b.addPoint(new h2d.col.Point(sx(k.time), sy(k.value)));
		}

		if (selection?.length > 1) {
			selectionBounds.setPosition(b.xMin, b.yMin);
			selectionBounds.setWidth(Std.int(b.width));
			selectionBounds.setHeight(Std.int(b.height));
		}
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
			for (s in selection) {
				keysBitmaps[s].bmp.alpha = 0.5;
				keysBitmaps[s].prevHandleBmp?.alpha = 0.5;
				keysBitmaps[s].nextHandleBmp?.alpha = 0.5;
			}

		selection = keys;

		if (selection != null)
			for (s in selection) {
				keysBitmaps[s].bmp.alpha = 1;
				keysBitmaps[s].prevHandleBmp?.alpha = 1;
				keysBitmaps[s].nextHandleBmp?.alpha = 1;
			}
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

	function fixKeys(keys : Array<Int>) {
		for (k in keys)
			fixKey(k);
	}

	function fixKey(k : Int) {
		var key = value.keys[k];

		var prev = value.keys[k-1];
		var next = value.keys[k+1];

		inline function addPrevH() {
			if(key.prevHandle == null)
				key.prevHandle = new hrt.prefab.Curve.CurveHandle(prev != null ? (prev.time - key.time) / 3 : -0.5, 0);
		}

		inline function addNextH() {
			if(key.nextHandle == null)
				key.nextHandle = new hrt.prefab.Curve.CurveHandle(next != null ? (next.time - key.time) / 3 : -0.5, 0);
		}

		switch(key.mode) {
			case Aligned:
				addPrevH();
				addNextH();
			case Free:
				addPrevH();
				addNextH();
			case Linear:
				key.nextHandle = null;
				key.prevHandle = null;
			case Constant:
				key.nextHandle = null;
				key.prevHandle = null;
		}

		if(key.time < 0)
			key.time = 0;
		// if(maxLength > 0 && key.time > maxLength)
		// 	key.time = maxLength;
		if(key.time > value.maxTime)
			key.time = value.maxTime;
		if(prev != null && key.time < prev.time)
			key.time = prev.time + 0.01;
		if(next != null && key.time > next.time)
			key.time = next.time - 0.01;
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}
#end