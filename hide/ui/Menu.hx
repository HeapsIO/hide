package hide.ui;

class Menu {

	public var root : nw.Menu;

	public function new( menu : Element) {
		root = new nw.Menu({type: Menubar});
		buildMenuRec(root,"",menu);
	}

	function buildMenuRec( menu : nw.Menu, path : String, e : Element ) {
		var cl = e.attr("class");
		if( cl != null ) {
			if( path == "" ) path = cl else path = path + "." + cl; 
		}
		var elt = e.get(0);
		switch( elt.nodeName ) {
		case "MENU":
			var submenu = null;
			if( elt.firstElementChild != null ) {
				submenu = new nw.Menu({type:ContextMenu});
				for( e in e.children().elements() )
					buildMenuRec(submenu, path, e);
			}
			var type : nw.MenuItem.MenuItemType = switch( e.attr("type") ) {
			case "checkbox": Checkbox;
			default: Normal;
			}
			var label = e.attr("label");
			if( label == null ) label = "???";
			var checked = e.attr("checked") == "checked";
			var m = new nw.MenuItem(submenu == null ? { label : label, type : type } : { label : label, type : type, submenu : submenu });
			if( type == Checkbox )
				m.checked = checked;
			if( e.attr("disabled") == "disabled" )
				m.enabled = false;
			m.click = function() {
				if( type == Checkbox ) {
					checked = !checked;
					e.attr("checked", checked ? "checked" : "");
					m.checked = checked;
				}
				e.click();
			};
			menu.append(m);
		case "SEPARATOR":
			menu.append(new nw.MenuItem({ label : null, type : Separator }));
		default:
			for( e in e.children().elements() )
				buildMenuRec(menu, path, e);
		}
	}

}
