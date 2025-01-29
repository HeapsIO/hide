package hide.comp;

typedef FancyItemState = {
	?open: Bool,
}

class FancyArray<T> extends hide.comp.Component {
	var itemState : Array<FancyItemState>;
	var name : String;
	var fancyItems: Element;

	public function new(parent: Element = null, e: Element = null, name: String, displayKey: String) {
		if (e == null)
			e = new Element("<fancy-array></fancy-array>");
		super(parent, e);

		fancyItems = new Element("<fancy-items></fancy-items>").appendTo(element);

		this.name = name;
		saveDisplayKey = displayKey + "/" + name;

		try {
			itemState = cast haxe.Json.parse(getDisplayState("state")) ?? [];
		} catch(_) {
			itemState = [];
		}
	}

	var dragKeyName : String;
	public function getDragKeyName() {
		if (dragKeyName == null)
			dragKeyName = '$name:index'.toLowerCase();
		return dragKeyName;
	}

	function saveState() {
		saveDisplayState("state", haxe.Json.stringify(itemState));
	}

	public function refresh() : Void {
		fancyItems.empty();
		var items = getItems();

		for (i => item in items) {
			var paramElement = new Element('<fancy-item>
				<header>
					<div class="reorder ico ico-reorder" draggable="true"></div>
					<div class="ico ico-chevron-down toggle-open"></div>
					<input type="text" value="${getItemName(item)}" class="fill"></input>
					<button-2 class="menu no-border"><div class="ico ico-ellipsis-v"/></button-2>
				</header>
			</fancy-item>').appendTo(fancyItems);

			itemState[i] ??= {};
			var state = itemState[i];
			var open : Bool = state.open ?? false;
			paramElement.toggleClass("folded", !open);

			var name = paramElement.find("input");

			if (setItemName != null) {
				name.on("change", (e) -> {
					setItemName(item, name.val());
				});

				name.on("keydown", (e) -> {
					if (e.keyCode == 13) {
						name.blur();
						e.stopPropagation();
					}
				});
			}

			name.on("contextmenu", (e) -> {
                e.stopPropagation();
            });

			var reorder = paramElement.find(".reorder");
			if (reorderItem != null) {

				inline function isAfter(e) {
					return e.clientY > (paramElement.offset().top + paramElement.outerHeight() / 2.0);
				}

				reorder.get(0).ondragstart = (e: js.html.DragEvent) -> {
					e.dataTransfer.setDragImage(paramElement.get(0), Std.int(paramElement.width()), 0);

					e.dataTransfer.setData(getDragKeyName(), '${i}');
					e.dataTransfer.dropEffect = "move";
				}

				paramElement.get(0).addEventListener("dragover", function(e : js.html.DragEvent) {
					if (!e.dataTransfer.types.contains(getDragKeyName()))
						return;
					var after = isAfter(e);
					paramElement.toggleClass("hovertop", !after);
					paramElement.toggleClass("hoverbot", after);
					e.preventDefault();
				});

				paramElement.get(0).addEventListener("dragleave", function(e : js.html.DragEvent) {
					if (!e.dataTransfer.types.contains(getDragKeyName()))
						return;
					paramElement.toggleClass("hovertop", false);
					paramElement.toggleClass("hoverbot", false);
				});

				paramElement.get(0).addEventListener("dragenter", function(e : js.html.DragEvent) {
					if (!e.dataTransfer.types.contains(getDragKeyName()))
						return;
					e.preventDefault();
				});

				paramElement.get(0).addEventListener("drop", function(e : js.html.DragEvent) {
					var toMoveIndex = Std.parseInt(e.dataTransfer.getData(getDragKeyName()));
					paramElement.toggleClass("hovertop", false);
					paramElement.toggleClass("hoverbot", false);
					if (i == null)
						return;
					var after = isAfter(e);

					var newIndex = i;

					if (!after) newIndex -= 1;
					if (toMoveIndex == newIndex)
						return;
					if (newIndex < i) {
						newIndex += 1;
					}
					reorderItem(toMoveIndex, newIndex);
				});
			} else {
				reorder.remove();
			}

			var toggleOpen = paramElement.find(".toggle-open");
			if (getItemContent != null) {
				var contentElement = getItemContent(item);
				if (contentElement != null) {
					var content = new Element("<content></content>").appendTo(paramElement);
					contentElement.appendTo(content);

					toggleOpen.on("click", (e) -> {
						state.open = !state.open;
						saveState();
						paramElement.toggleClass("folded", !state.open);
					});
				} else {
					toggleOpen.remove();
				}
			} else {
				toggleOpen.remove();
			}

			if (removeItem != null) {
				paramElement.find("header").get(0).addEventListener("contextmenu", function (e : js.html.MouseEvent) {
					e.preventDefault();
					hide.comp.ContextMenu.createFromEvent(e, [
						{label: "Delete", click: () -> removeItem(i)}
					]);
				});

				var menu = paramElement.find(".menu");
				menu.on("click", (e) -> {
					e.preventDefault();
					hide.comp.ContextMenu.createDropdown(menu.get(0), [
						{label: "Delete", click: () -> removeItem(i)}
					]);
				});
			}			paramElement.find("header").get(0).addEventListener("contextmenu", function (e : js.html.MouseEvent) {
				e.preventDefault();
				hide.comp.ContextMenu.createFromEvent(e, [
					{label: "Delete", click: () -> removeItem(i)}
				]);
			});

			var menu = paramElement.find(".menu");
			menu.on("click", (e) -> {
				e.preventDefault();
				hide.comp.ContextMenu.createDropdown(menu.get(0), [
					{label: "Delete", click: () -> removeItem(i)}
				]);
			});
		}
	}

	public var reorderItem : (oldIndex: Int, newIndex: Int) -> Void = null;

	/**
		If left null, no item cannot be added to the list
	**/
	public var insertItem : (index: Int) -> Void = null;

	/**
		If left null, the items cannot be removed from the list
	**/
	public var removeItem : (index: Int) -> Void = null;

	/**
		If left null, the item name is read only
	**/
	public var setItemName: (item: T, name: String) -> Void = null;

	/**
		If left null, or if the function returns null, the item cannot be open
	**/
	public var getItemContent: (item: T) -> Element;

	public dynamic function getItems() : Array<T> {
		return [];
	}

	public dynamic function getItemName(item: T) : String {
		return null;
	}

}