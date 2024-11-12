package hide.comp;

typedef ContextMenuItem = hide.comp.ContextMenu2.MenuItem;

class ContextMenu {
	public function new( config : Array<ContextMenuItem> ) {
		var ide = hide.Ide.inst;
		#if js
		ContextMenu2.createFromPoint(ide.mouseX, ide.mouseY, config);
		#end
	}
}