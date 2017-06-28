package nw;

@:enum abstract MenuItemType(String) {
	var Normal = "normal";
	var Checkbox = "checkbox";
	var Separator = "separator";
}

extern class MenuItem {

	public var checked : Bool;
	public var enabled : Bool;

	public function new( options : { label : String, ?icon : String, ?type : MenuItemType, ?submenu : Menu } ) : Void;
	public dynamic function click() : Void;
}