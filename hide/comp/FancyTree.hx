package hide.comp;

/**
	TODO :
		[ ] Rename item by double click / F2 / Context menu
		[ ] Customisable context menu
		[ ] Customisable end of list icons
		[ ] Custom "pills" info near the title
		[ ] Fold animation
		[ ] General styling

**/

enum MoveAllowedOperations {
	Reorder;
	Reparent;
}

typedef MoveFlags = haxe.EnumFlags<MoveAllowedOperations>;

typedef TreeItemData<TreeItem> = {?element: js.html.Element, ?header: js.html.Element, ?children: Array<TreeItem>, ?parent: TreeItem, ?depth: Int, ?item: TreeItem, ?open: Bool};

class FancyTree<TreeItem : Dynamic> extends hide.comp.Component {
	public var itemMap : Map<{}, TreeItemData<TreeItem>> = [];

	// Forced to use another object because itemMap can't use null as an index for some reason
	var rootData : TreeItemData<TreeItem> = {};

	public var moveFlags : MoveFlags = MoveFlags.ofInt(0);

	var selection : Map<{}, Bool> = [];
	var currentItem : TreeItem;

	public function new(parent: Element) {
		var el = new Element('<fancy-tree tabindex="-1"><fancy-wrapper></fancy-wrapper></fancy-tree>');
		super(parent, el);

		var fancyTree = el.get(0);
		fancyTree.onkeydown = (e: js.html.KeyboardEvent) -> {
			var delta = 0;
			if (e.key == "ArrowUp") {
				delta -= 1;
			}
			if (e.key == "ArrowDown") {
				delta += 1;
			}
			if (e.key == "PageUp") {
				delta -= 10;
			}
			if (e.key == "PageDown") {
				delta += 10;
			}

			if (delta != 0) {
				e.stopPropagation();
				moveCurrent(delta);
				return;
			}

			if (e.key == "ArrowRight" && hasChildren(currentItem)) {
				e.stopPropagation();

				var currentData = getDataOrRoot(currentItem);
				if (currentData == null || currentData.open) {
					moveCurrent(1);
				}
				else if (currentData != null && !currentData.open) {
					toggleItemOpen(currentItem, true);
				}
				return;
			}
			if (e.key == "ArrowLeft") {
				e.stopPropagation();

				var currentData = getDataOrRoot(currentItem);
				if (currentData != null) {
					var anyChildren = hasChildren(currentItem);
					var goToParent = !anyChildren && currentData.parent != null;
					goToParent = goToParent || anyChildren && !currentData.open;

					if (goToParent) {
						setCurrent(currentData.parent);
					} else if(anyChildren) {
						toggleItemOpen(currentItem, false);
					}
				}
				return;
			}

			if (e.key == "Enter") {
				e.stopPropagation();
				clearSelection();
				if (currentItem != null) {
					setSelection(currentItem, true);
				}
				onSelectionChanged();
				return;
			}
		};

		resetItemCache();
	}

	/**
		Called for each of your items in the tree. for the root elements, get called with null as a parameter
	**/
	public dynamic function getChildren(item: TreeItem) : Array<TreeItem> {return null;}

	/**
		Called to know if an item in the tree can be opened or has children. Default to calling getChildren and seeing if it returns false.
		Set this function to optimise the initial loading of the tree if getChildren is expensive
	**/
	public dynamic function hasChildren(item : TreeItem) : Bool {
		var children = getChildren(item);
		if (children == null)
			return false;
		return children.length > 0;
	}

	/**
		To customise the icon of an element
	**/
	public dynamic function getIcon(item: TreeItem) : js.html.Element {return null;}

	/**
		The display name of an item
	**/
	public dynamic function getName(item: TreeItem) : String {return "undefined";}

	/**
		Called when the selected items in the tree changed
	**/
	public dynamic function onSelectionChanged() {
	}

	/**
		Used to filter if an item can be reparented to another. Only called if MoveFlags contains Reparent.
		If this function return false, the reparent operation between the two arguments is not allowed
	**/
	public dynamic function canReparentTo(item: TreeItem, newParent: TreeItem) : Bool {
		return true;
	}

	/**
		Called to handle a reparent/reorder operation. newIndex will be -1 if the current MoveFlags don't contain can reorder, and t
	**/
	public dynamic function onMove(item: TreeItem, newParent: TreeItem, newIndex: Int) : Void {

	}

	public function getSelectedItems() : Array<TreeItem> {
		return [for (item => _ in selection) cast item];
	}

	/**
		Destroy and recreate all the elements in the tree.
		All the cached children will be erased
	**/
	public function rebuildTree() {
		resetItemCache();
		redrawItems();
	}

	function resetItemCache() {
		itemMap.clear();
		rootData = {element: element.find("fancy-wrapper").get(0), depth: 0, open: true};
	}

	function redrawItems() {
		untyped rootData.element.replaceChildren();
		initChildren(null);
	}

	function toggleItemOpen(item: TreeItem, ?force: Bool ) : Void {
		initChildren(item);

		var data = itemMap.get(cast item);
		data.open = force ?? !data.open;
		data.element.classList.toggle("open", data.open);
	}

	function initChildren(item: TreeItem) : Void {
		var data = getDataOrRoot(item);
		if (data?.element == null || data?.depth == null)
			throw "Data is not properly initialised";

		if (data.children == null) {
			data.children = getChildren(item);

			if (data.children != null) {
				var childrenElement = js.Browser.document.createElement("fancy-tree-children");
				data.element.append(childrenElement);

				for (child in data.children) {
					if (child == null)
						continue;
					var childElem = getElement(child, item, data.depth + 1);
					if (childElem != null)
						childrenElement.append(childElem);
				}
			}
		}
	}

	function getDataOrRoot(item: TreeItem) {
		if (item != null) {
			return hrt.tools.MapUtils.getOrPut(itemMap, cast item, {item: item});
		} else {
			return rootData;
		}
	}

	function getElement(item : TreeItem, parent: TreeItem, depth: Int) : js.html.Element {
		var data = getDataOrRoot(item);
		data.depth = depth;
		data.parent = parent;

		if (data.element == null) {
			data.element = js.Browser.document.createElement("fancy-tree-item");
			data.element.style.setProperty("--depth", Std.string(depth));

			var header = js.Browser.document.createElement("fancy-tree-header");
			data.header = header;
			data.element.append(header);
			{
				var fold = js.Browser.document.createElement("fancy-tree-icon");
				header.append(fold);

				if (hasChildren(item)) {
					fold.classList.add("caret");
					fold.addEventListener("click", (e) -> {
						toggleItemOpen(item);
					});
				}

				var iconContent = getIcon(item);
				if (iconContent != null) {
					var icon = js.Browser.document.createElement("fancy-tree-icon");
					icon.append(iconContent);
					header.append(icon);
				}

				var nameElement = js.Browser.document.createElement("fancy-tree-name");
				var name = getName(item) ?? "undefined";
				header.title = name;
				nameElement.innerText = name;
				header.append(nameElement);

				header.onclick = (e: js.html.MouseEvent) -> {
					var lastSelected = currentItem;
					if (!e.ctrlKey) {
						clearSelection();
					}

					if (e.shiftKey) {
						var flat = flattenTreeItems();
						var currentIndex = flat.indexOf(currentItem);
						var newIndex = flat.indexOf(item);

						var min = hxd.Math.imin(currentIndex, newIndex);
						var max = hxd.Math.imax(currentIndex, newIndex);

						for (i in min...max + 1) {
							setSelection(flat[i], true);
						}
					} else {
						setSelection(item, !selection.exists(cast item));
					}
					setCurrent(item);
					onSelectionChanged();
				}
			}
		}

		return data.element;
	}

	public function clearSelection() {
		for (item => _ in selection) {
			var item : TreeItem = cast item;
			refreshItemSelection(item, false);
		}
		selection.clear();
	}

	public function setSelection(item: TreeItem, newStatus: Bool) {
		if (newStatus == true)
			selection.set(cast item, true);
		else
			selection.remove(cast item);
		refreshItemSelection(item, newStatus);
	}

	public function setCurrent(item: TreeItem) {
		if (currentItem != null) {
			var data = getDataOrRoot(currentItem);
			data?.element?.classList.remove("current");
		}
		currentItem = item;
		var data = getDataOrRoot(item);
		data?.element?.classList.add("current");
	}

	public function flattenTreeItems() : Array<TreeItem> {
		var flat : Array<TreeItem> = [];
		function flatten(item: TreeItem) {
			var data = getDataOrRoot(item);
			if (data.children != null && data.open) {
				for (child in data.children) {
					flat.push(child);
					flatten(child);
				}
			}
		}
		flatten(null);
		return flat;
	}

	public function moveCurrent(delta: Int) {
		if (delta == 0)
			return;

		if (currentItem == null) {
			if (rootData.children == null)
				return;

			currentItem = rootData.children[0];
			if (currentItem == null)
				return;
		}

		var flat = flattenTreeItems();

		var currentIndex = flat.indexOf(currentItem);
		if (currentIndex < 0)
			throw '$currentItem no in flat array';

		var nextIndex = hxd.Math.iclamp(currentIndex + delta, 0, flat.length-1);

		if (nextIndex != currentIndex) {
			setCurrent(flat[nextIndex]);
		}
	}

	function refreshItemSelection(item: TreeItem, status: Bool) {
		var data = itemMap.get(cast item);
		if (data?.element == null)
			return;
		data.element.classList.toggle("selected", status);
	}
}