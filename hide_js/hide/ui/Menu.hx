package hide.ui;

class Menu {

	public var root : electron.Menu;

	public function new( menu : Element) {
		root = new electron.Menu();
		buildMenuRec(root,"",menu);
	}

	function buildMenuRec( menu : electron.Menu, path : String, e : Element ) {
		var cl = e.attr("class");
		if( cl != null ) {
			if( path == "" ) path = cl else path = path + "." + cl;
		}
		var elt = e.get(0);
		switch( elt.nodeName ) {
		case "MENU":
			var submenu = null;
			if( elt.firstElementChild != null ) {
				submenu = new electron.Menu();
				for( e in e.children().elements() )
					buildMenuRec(submenu, path, e);
			}
			var type : electron.MenuItem.MenuItemType = switch( e.attr("type") ) {
			case "checkbox": Checkbox;
			default: Normal;
			}
			var label = e.attr("label");
			if( label == null ) label = "???";
			var checked = e.prop("checked") || e.attr("checked") == "checked";
			var m = new electron.MenuItem(submenu == null ? { label : label, type : type } : { label : label, type : type, submenu : submenu });
			if( type == Checkbox )
				m.checked = checked;
			if( e.attr("disabled") == "disabled" )
				m.enabled = false;
			m.click = function() {
				if( type == Checkbox ) {
					checked = !checked;
					e.prop("checked", checked);
					m.checked = checked;
				}
				e.click();
			};
			menu.append(m);
		case "SEPARATOR":
			menu.append(new electron.MenuItem({ label : null, type : Separator }));
		default:
			for( e in e.children().elements() )
				buildMenuRec(menu, path, e);
		}
	}

}
