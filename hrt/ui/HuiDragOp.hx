package hrt.ui;

#if hui
class HuiDragOp {
	public var origin: HuiElement;
	public var data: Dynamic;
	public var type: String;

	function new(origin: HuiElement, type: String, data: Dynamic) {
		this.origin = origin;
		this.data = data;
		this.type = type;
	}
}
#end