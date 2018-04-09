package hide.comp;

typedef ContextMenuItem = {
	var label : String;
	@:optional var menu : Array<ContextMenuItem>;
	@:optional var click : Void -> Void;
	@:optional var enabled : Bool;
	@:optional var checked : Bool;
	@:optional var isSeparator : Bool;
}

class ContextMenu {

	public function new( config : Array<ContextMenuItem> ) {
		var menu = makeMenu(config);
		var ide = hide.Ide.inst;
		menu.popup(ide.mouseX, ide.mouseY);
	}

	function makeMenu( config : Array<ContextMenuItem> ) {
		var m = new nw.Menu({type:ContextMenu});
		for( i in config )
			m.append(makeMenuItem(i));
		return m;
	}

	function makeMenuItem(i:ContextMenuItem) {
		var mconf : nw.MenuItem.MenuItemOptions = { label : i.label, type : i.checked != null ? Checkbox : i.isSeparator ? Separator : Normal };
		if( i.menu != null ) mconf.submenu = makeMenu(i.menu);
		var m = new nw.MenuItem(mconf);
		if( i.checked != null ) m.checked = i.checked;
		if( i.enabled != null ) m.enabled = i.enabled;
		m.click = i.click;
		return m;
	}

}