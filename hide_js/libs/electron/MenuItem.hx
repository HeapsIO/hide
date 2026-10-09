package electron;

enum abstract MenuItemType(String) {
	var Normal = "normal";
	var Checkbox = "checkbox";
	var Separator = "separator";
}

typedef MenuItemOptions = { label : String, ?type : MenuItemType, ?submenu : Menu };

class MenuItem {

	static var UID = 0;

	public var id(default, null) : String;
	public var label(default, null) : String;
	public var type(default, null) : MenuItemType;
	public var submenu(default, null) : Menu;
	public var checked(default, set) : Bool = false;
	public var enabled(default, set) : Bool = true;

	var attached = false;

	public function new( options : MenuItemOptions ) {
		id = "m" + (UID++);
		label = options.label;
		type = options.type == null ? Normal : options.type;
		submenu = options.submenu;
	}

	public dynamic function click() {
	}

	function set_checked( b : Bool ) {
		if( attached && b != checked ) Ipc.call("win.updateMenuItem", id, { checked : b });
		return checked = b;
	}

	function set_enabled( b : Bool ) {
		if( attached && b != enabled ) Ipc.call("win.updateMenuItem", id, { enabled : b });
		return enabled = b;
	}

	function toTemplate( all : Map<String, MenuItem> ) : Dynamic {
		attached = true;
		all.set(id, this);
		return {
			id : id,
			label : label,
			type : type,
			checked : checked,
			enabled : enabled,
			submenu : submenu == null ? null : @:privateAccess submenu.toTemplate(all),
		};
	}

}
