package hide.comp;


class FancyArray<T> extends hide.comp.Component {
	public function new(parent: Element, e: Element, undo: hide.ui.UndoHistory) {
		if (e == null)
			e = new Element("<ul></ul>");
		super(parent, e);
		element.addClass("fancy-array");
	}

	public function refresh() : Void {
		element.empty();
		var items = getItems();


	}

	public var reorder : (oldIndex, newIndex) -> Void = null;
	public var insert : (index) -> Void = null;
	public var remove : (index) -> Void = null;

	dynamic function getItems() : Array<T> {
		return [];
	}

	dynamic function getItemName(item: T) : String {
		return null;
	}

	dynamic function setItemName(name: String, item: T) : Void {

	}
}