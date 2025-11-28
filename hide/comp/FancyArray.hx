package hide.comp;

typedef FancyItemState = {
	?open: Bool,
}

class FancyArray<T> extends hide.comp.Component {
	var itemState : Array<FancyItemState>;
	var name : String;
	var fancyItems: Element;
	var itemsElements : Array<Element> = [];

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

	/**
		Check if the given drag event comes from this FancyArray,
		and if that's the case, returns the relevant Item index that
		was dragged from this array
	**/
	public function getDragIndex(e:js.html.DragEvent) : Null<Int> {
		if (!e.dataTransfer.types.contains(getDragKeyName()))
			return null;
		return Std.parseInt(e.dataTransfer.getData(getDragKeyName()));
	}

	function saveState() {
		saveDisplayState("state", haxe.Json.stringify(itemState));
	}

	public function toggleItem(index:Int, ?forceState: Bool) {
		itemState[index].open = forceState ?? !itemState[index].open;
		saveState();
		fancyItems.children()[index].classList.toggle("open", itemState[index].open);
	}

	public function refresh() : Void {
		fancyItems.empty();
		var items = getItems();
		itemsElements = [];

		for (i => item in items) {
			var paramElement = new Element('<fancy-item>
				<fancy-item-header class="fancy-small">
					<fancy-button class="quieter reorder" draggable="true">
						<div class="ico ico-reorder"></div>
					</fancy-button>
					<fancy-button class="quieter toggle-open">
						<div class="ico ico-chevron-right"></div>
					</fancy-button>
					<input type="text" value="${getItemName(item)}" class="fill title-text"></input>
					<fancy-button class="menu quieter"><div class="ico ico-ellipsis-v"></div></fancy-button>
				</fancy-item-header>
			</fancy-item>').appendTo(fancyItems);

			itemsElements.push(paramElement);

			itemState[i] ??= {};
			var state = itemState[i];
			var open : Bool = state.open ?? false;
			paramElement.toggleClass("open", open);

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
			} else {
				name.attr("disabled", "true");
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
					var content = new Element("<fancy-item-content></fancy-item-content>").appendTo(paramElement);
					contentElement.appendTo(content);

					toggleOpen.on("click", (e) -> {
						toggleItem(i);
					});
				} else {
					toggleOpen.remove();
				}
			} else {
				toggleOpen.remove();
			}

			var dropdown = getDropdownMenu(i);
			paramElement.find("fancy-item-header").get(0).addEventListener("contextmenu", function (e : js.html.MouseEvent) {
				e.preventDefault();
				e.stopPropagation();
				if (dropdown.length > 0) {
					hide.comp.ContextMenu.createFromEvent(e, dropdown);
				}
			});

			var menu = paramElement.find(".menu");
			if (dropdown.length > 0) {
				menu.on("click", (e) -> {
					e.preventDefault();
					e.stopPropagation();
					hide.comp.ContextMenu.createDropdown(menu.get(0), getDropdownMenu(i));
				});
			} else {
				menu.remove();
			}

			if (customizeHeader != null) {
				customizeHeader(item, paramElement.find("fancy-item-header"));
			}
		}
	}

	public function getDropdownMenu(index: Int) : Array<hide.comp.ContextMenu.MenuItem> {
		var menu : Array<hide.comp.ContextMenu.MenuItem> = [];

		if (removeItem != null) {
			menu.push({label: "Delete", click: () -> removeItem(index)});
		}

		return menu;
	}

	// Open target item index, and make it flash briefly
	public function reveal(index: Int) {
		for (i => param in itemsElements) {
			toggleItem(i, i == index);
		}
		var param = itemsElements[index].get(0);
		param.onanimationend = (e) -> {
			param.classList.remove("reveal");
		};
		param.classList.remove("reveal");
		param.classList.add("reveal");
	}

	// Focus the title bar of the given index for editing
	public function editTitle(index: Int) {
		var a = itemsElements[index].find(".title-text");
		a.focus();
		a.select();
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

	/**
		If set, the function will be called after the header element is created so the user could customize it's appearence
		like adding icons or type information
	**/
	public var customizeHeader: (item: T, header: Element) -> Void;

	public dynamic function getItems() : Array<T> {
		return [];
	}

	public dynamic function getItemName(item: T) : String {
		return null;
	}

}