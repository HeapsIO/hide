package electron;

/**
	A native menu, attached to a window by setting `Window.menu`
**/
class Menu {

	public var items(default, null) : Array<MenuItem> = [];

	public function new() {
	}

	public function append( m : MenuItem ) {
		items.push(m);
	}

	function toTemplate( all : Map<String, MenuItem> ) : Array<Dynamic> {
		return [for( m in items ) @:privateAccess m.toTemplate(all)];
	}

}
