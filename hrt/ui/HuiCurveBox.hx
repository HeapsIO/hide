package hrt.ui;

#if hui
@:access(hrt.prefab.Curve)
class HuiCurveBox extends HuiElement {
	static var SRC = <hui-curve-box>
	</hui-curve-box>

	public static var CURVE_COLOR = 0x05f505;
	public static var CURVE_WIDTH = 1;
	public static var CURVE_PRECISION = 500;

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
				uiBase.addPopup(editor, { object: Element(this), directionX: StartInside, directionY: EndOutside }, false);

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
		value = hxd.res.Loader.currentInstance.load("prefabs/simple.prefab").toPrefab().load().getOpt(hrt.prefab.Curve);
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

	var root : h2d.Object;
	var gridGraphics : h2d.Graphics;

	public function new (b : HuiCurveBox, ?parent) {
		super(parent);
		initComponent();

		root = new h2d.Object(this);
		this.getProperties(root).isAbsolute = true;
		
		onAfterReflow = () -> {
			updateAnchor(true);
			refreshGrid();
		}
	}

	public function refreshGrid() {
		if (gridGraphics == null)
			gridGraphics = new h2d.Graphics(root);
		
		gridGraphics.clear();
		gridGraphics.setPosition(0, this.calculatedHeight);
		gridGraphics.lineStyle(GRID_WIDTH, GRID_COLOR, 1);
		gridGraphics.moveTo(0, 0);

		var columnCount = 10;
		var lineCount = 10;
		for (x in 0...columnCount) {
			gridGraphics.moveTo(x * (calculatedWidth / columnCount), 0);
			gridGraphics.lineTo(x * (calculatedWidth / columnCount), -calculatedHeight);
			for (y in 0...lineCount) {
				gridGraphics.moveTo(0, y * (-calculatedHeight / lineCount));
				gridGraphics.lineTo(calculatedWidth, y * (-calculatedHeight / lineCount));
			}
		}
	}


	public function refresh() {
		// if (this.graphics == null)
		// 	graphics = new h2d.Graphics(root);

		// graphics.setPosition(0, this.calculatedHeight);
		// graphics.clear();
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}
#end