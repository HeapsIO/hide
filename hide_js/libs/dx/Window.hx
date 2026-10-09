package dx;

/**
	JS replacement of hldx's dx.Window, as used by the DX12 driver : the window is the
	page canvas (#webgl, like hxd.Window), where the back buffers are displayed.
**/
class Window {

	static var windows(get, null) : Array<Window>;

	public var canvas(default, null) : js.html.CanvasElement;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var vsync : Bool = true;

	public function new( canvas : js.html.CanvasElement ) {
		this.canvas = canvas;
	}

	function get_width() {
		return Math.round(canvas.getBoundingClientRect().width * js.Browser.window.devicePixelRatio);
	}

	function get_height() {
		return Math.round(canvas.getBoundingClientRect().height * js.Browser.window.devicePixelRatio);
	}

	static function get_windows() {
		if( windows == null ) {
			var canvas : js.html.CanvasElement = cast js.Browser.document.getElementById("webgl");
			if( canvas == null ) throw "Missing canvas #webgl";
			windows = [new Window(canvas)];
		}
		return windows;
	}
}
