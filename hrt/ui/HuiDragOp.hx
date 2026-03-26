package hrt.ui;

#if hui
class HuiDragOp {
	public var origin: HuiElement;
	public var data: Dynamic;
	public var type: String;

	public var event: hxd.Event;

	var lastOver: HuiElement;

	function new(origin: HuiElement, type: String, data: Dynamic) {
		this.origin = origin;
		this.data = data;
		this.type = type;
	}

	function setLastOver(newElement: HuiElement) {
		if (lastOver != null)
			lastOver.onDragOut(this);
		lastOver = newElement;
	}
}
#end