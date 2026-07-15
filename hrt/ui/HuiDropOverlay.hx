package hrt.ui;


#if hui

class HuiDropOverlay extends HuiElement {
	static var SRC =
		<hui-drop-overlay>
		</hui-drop-overlay>

	public var acceptAny(never, set) : Bool;
	public var accept(never, set) : Bool;

	function set_acceptAny(v) {
		dom.toggleClass("accept-drop-any", v);
		return v;
	}

	function set_accept(v) {
		dom.toggleClass("accept-drop", v);
		return v;
	}

	public function reset() {
		acceptAny = false;
		accept = false;
	}
}
#end