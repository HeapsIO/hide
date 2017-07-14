package golden;

extern class Container {

	public var width(default,null) : Int;
	public var height(default,null) : Int;
	public var parent : ContentItem;

	public var tab : Tab;
	public var title(default,null) : String;
	public var layoutManager(default,null) : Layout;
	public var isHidden(default,null) : Bool;

	public function getElement() : js.jquery.JQuery;

	public function setTitle( title : String ) : Void;
	public function setState( state : Dynamic ) : Void;
	public function setSize( width : Int, height : Int ) : Void;

	public function hide() : Void;
	public function show() : Bool;

	public function close() : Bool;

	public function on( type : String, callb : Event<Container> -> Void ) : Void;
	public function off( type : String ) : Void;

}
