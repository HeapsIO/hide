package dx;

/**
	JS replacement of hldx's dx.Window, as used by the DX12 driver : the window is the canvas of
	the current hxd.Window, where the back buffers are displayed. The driver is shared by the engines
	of all the canvas (see h3d.Engine) : it is resized and presented for the engine rendered.
**/
class Window {

	static var windows : Array<Window> = [new Window()];

	public var canvas(get, never) : js.html.CanvasElement;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var vsync : Bool = true;

	function new() {
	}

	function get_canvas() : js.html.CanvasElement {
		return @:privateAccess hxd.Window.getInstance().canvas;
	}

	function get_width() {
		return Math.round(canvas.getBoundingClientRect().width * js.Browser.window.devicePixelRatio);
	}

	function get_height() {
		return Math.round(canvas.getBoundingClientRect().height * js.Browser.window.devicePixelRatio);
	}
}
