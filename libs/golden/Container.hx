package golden;

extern class Container {

	public var width(default,null) : Int;
	public var height(default,null) : Int;
	//public var parent :
	//public var tab
	public var title(default,null) : String;
	public var layoutManager(default,null) : Layout;
	public var isHidden(default,null) : Bool;

	public function getElement() : js.jquery.JQuery;

	public function setTitle( title : String ) : Void;

}
