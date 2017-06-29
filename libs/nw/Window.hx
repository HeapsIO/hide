package nw;

extern class Window {

	public var x : Int;
	public var y : Int;
	public var width : Int;
	public var height : Int;

	public var window : js.html.Window;

	public var menu : Menu;
	public var title : String;

	public function showDevTools() : Void;

	public function moveTo( x : Int, y : Int ) : Void;
	public function moveBy( dx : Int, dy : Int ) : Void;
	public function resizeTo( w : Int, h : Int ) : Void;
	public function resizeBy( dw : Int, dh : Int ) : Void;

	public function maximize() : Void;
	public function minimize() : Void;
	public function restore() : Void;
	public function on( event : String, callb : Void -> Void ) : Void;

	public function show( b : Bool ) : Void;

	public static function get() : Window;

}