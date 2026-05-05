package hrt.ui;

#if hui
@:allow(hrt.ui.HuiBase)
class HuiDragOp {
	public var origin: HuiElement;
	public var data: Dynamic;
	public var type: String;

	var base : HuiBase;
	var previewWidget: HuiElement;
	var previewOffsetX: Int;
	var previewOffsetY: Int;

	public var event: hxd.Event;
	public var acceptDrop: Bool = false;


	var lastOver: HuiElement;

	function new(origin: HuiElement, type: String, data: Dynamic) {
		this.origin = origin;
		this.data = data;
		this.type = type;
	}

	function dispose() {
		if (previewWidget != null) {
			previewWidget.remove();
		}
	}

	function setLastOver(newElement: HuiElement) {
		if (lastOver != null)
			lastOver.onDragOut(this);
		lastOver = newElement;
		trace("Set last over", newElement);
	}

	public function setPreview(newElement: HuiElement, offsetX: Int, offsetY: Int) {
		previewWidget = newElement;
		base.addChild(previewWidget);
		var props = base.getProperties(previewWidget);
		props.isAbsolute = true;
		previewWidget.dom.addClass("drag-preview");
		previewOffsetX = offsetX;
		previewOffsetY = offsetY;

		var scene = base.getScene();
		previewWidget.dom.applyStyle(base.style);
		updatePreviewPos(scene.mouseX, scene.mouseY);
	}

	public function setPreviewText(text: String) {
		var prev = new HuiDragDropPreview();
		prev.text.text = text;
		setPreview(prev, -4, -16);
	}

	function updatePreviewPos(x: Float, y: Float) {
		var scene = base.getScene();

		x /= scene.viewportScaleX;
		y /= scene.viewportScaleY;

		var props = base.getProperties(previewWidget);
		x += props.paddingLeft;
		y += props.paddingTop;

		previewWidget.x = x;
		previewWidget.y = y;
	}
}

class HuiDragDropPreview extends HuiElement {
	static var SRC =
		<hui-drag-drop-preview>
			<hui-text("") public id="text"/>
		</hui-drag-drop-preview>
}
#end