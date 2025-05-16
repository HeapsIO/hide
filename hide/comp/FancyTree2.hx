package hide.comp;

/**
	TODO :
		[ ] Selection
		[ ] Current Item
		[ ] Arrow navigation
		[ ] Search
		[ ] Don't loose "current item" on search
		[ ] Rename item
		[ ] Move items
		[ ] Save fold state
		[ ] Customisable context menu
		[ ] Customisable end of list icons
		[ ] Custom "pills" info near the title
		[X] General styling

**/

enum FilterFlag {
	Visible;
	MatchSearch;
	Open;
}

typedef FilterFlags = haxe.EnumFlags<FilterFlag>;

typedef TreeItemData2<TreeItem> = {element: js.html.Element, ?searchRanges: SearchRanges, item: TreeItem, name: String, ?iconCache: String, open: Bool, filterState: FilterFlags, children: Array<TreeItemData2<TreeItem>>, parent: TreeItemData2<TreeItem>, depth: Int};

typedef SearchRanges = Array<Int>;
class FancyTree2<TreeItem> extends hide.comp.Component {
	var rootData : Array<TreeItemData2<TreeItem>> = [];
	public var itemMap : Map<{}, TreeItemData2<TreeItem>> = [];
	var selection : Map<{}, Bool> = [];
	var openState: Map<String, Bool> = [];
	var currentItem : TreeItem;
	var searchBar : hide.comp.FancySearch = null;

	var flatData : Array<TreeItemData2<TreeItem>>;

	var itemContainer : js.html.Element;
	var scroll : js.html.Element;
	var currentSearch : String = "";

	public function new(parent: Element) {
		var el = new Element('<fancy-tree2 tabindex="-1">
				<fancy-search></fancy-search>
				<fancy-scroll>
				<fancy-item-container>
				</fancy-item-container>
				</fancy-scroll>
			</fancy-tree2>'
		);
		super(parent, el);

		searchBar = new FancySearch(null, element.find("fancy-search"));
		searchBar.onSearch = (search, _) -> {
			currentSearch = search.toLowerCase();
			queueRefresh(true, true);
		}

		scroll = el.find("fancy-scroll").get(0);
		itemContainer = el.find("fancy-item-container").get(0);
		lastHeight = null;

		var fancyTree = el.get(0);
		fancyTree.onkeydown = (e: js.html.KeyboardEvent) -> {

			if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
				e.stopPropagation();
				e.preventDefault();

				searchBar.toggleSearch(true, true);
			}

			// if (hide.ui.Keys.matchJsEvent("rename", e, ide.currentConfig) && selection.iterator().hasNext()) {
			// 	e.stopPropagation();
			// 	e.preventDefault();

			// 	beginRename(cast selection.keyValueIterator().next().key);
			// }

			// if (e.key == "Escape") {
			// 	if (searchBar.isOpen()) {
			// 		e.stopPropagation();
			// 		e.preventDefault();

			// 		searchBar.toggleSearch(false);
			// 		fancyTree.focus();
			// 		resetSearch(null);
			// 	}
			// }

			// var delta = 0;
			// switch (e.key) {
			// 	case "ArrowUp":
			// 		delta -= 1;
			// 	case "ArrowDown":
			// 		delta += 1;
			// 	case "PageUp":
			// 		delta -= 10;
			// 	case "PageDown":
			// 		delta += 10;
			// }

			// if (delta != 0) {
			// 	e.stopPropagation();
			// 	e.preventDefault();
			// 	moveCurrent(delta);
			// 	return;
			// }

			// if (currentItem == null)
			// 	return;

			// if (e.key == "ArrowRight" && hasChildren(currentItem)) {
			// 	e.stopPropagation();
			// 	e.preventDefault();

			// 	var currentData = getDataOrRoot(currentItem);
			// 	if (currentData == null || isDataVisuallyOpen(currentData)) {
			// 		moveCurrent(1);
			// 	}
			// 	else if (currentData != null && !isDataVisuallyOpen(currentData)) {
			// 		toggleItemOpen(currentItem, true);
			// 		saveState();
			// 	}
			// 	return;
			// }
			// if (e.key == "ArrowLeft") {
			// 	e.stopPropagation();
			// 	e.preventDefault();

			// 	var currentData = getDataOrRoot(currentItem);
			// 	if (currentData != null) {
			// 		var anyChildren = hasChildren(currentItem);
			// 		var goToParent = !anyChildren && currentData.parent != null;
			// 		goToParent = goToParent || anyChildren && !isDataVisuallyOpen(currentData);

			// 		if (goToParent && currentData.parent != null) {
			// 			setCurrent(currentData.parent);
			// 		} else if(anyChildren && currentItem != null) {
			// 			toggleItemOpen(currentItem, false);
			// 			saveState();
			// 		}
			// 	}
			// 	return;
			// }

			// if (e.key == "Enter") {
			// 	e.stopPropagation();
			// 	e.preventDefault();

			// 	clearSelection();
			// 	if (currentItem != null) {
			// 		setSelection(currentItem, true);
			// 	}
			// 	onSelectionChanged();
			// 	return;
			// }
		};

		//resetItemCache();

		scroll.onscroll = (e) -> queueRefresh(false, false);

	}


	/**
		To customise the icon of an element
	**/
	public dynamic function getIcon(item: TreeItem) : String {return null;}

	/**
		The display name of an item
	**/
	public dynamic function getName(item: TreeItem) : String {return "undefined";}

	/**
		If items in the tree can have the same name, this function should return a unique name for each of them.
		Used to save the state of the open folders in the tree
	**/
	public dynamic function getUniqueName(item: TreeItem) : String {return getName(item);}

	/**
		Called when the selected items in the tree changed
	**/
	public dynamic function onSelectionChanged() {
	}

	/**
		Used to filter if an item can be reparented to another. Only called if MoveFlags contains Reparent.
		If this function return false, the reparent operation between the two arguments is not allowed
	**/
	public dynamic function canReparentTo(items: Array<TreeItem>, newParent: TreeItem) : Bool {
		return true;
	}

	/**
		Called to handle a reparent/reorder operation. newIndex will be -1 if the current MoveFlags don't contain can reorder, and t
	**/
	public dynamic function onMove(items: Array<TreeItem>, newParent: TreeItem, newIndex: Int) : Void {
	}

	/**
		Called when the user renamed the item via F2 / Context menu
	**/
	public dynamic function onNameChange(item: TreeItem, newName: String) : Void {
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

	public function getSelectedItems() : Array<TreeItem> {
		return [for (item => _ in selection) cast item];
	}

	public function generateChildren(parentData: TreeItemData2<TreeItem>) : Array<TreeItemData2<TreeItem>> {
		var childrenTreeItem = getChildren(parentData?.item);

		var childrenData : Array<TreeItemData2<TreeItem>> = [];
		if (childrenTreeItem != null) {
			for (childItem in childrenTreeItem) {
				var childData : TreeItemData2<TreeItem>;
				childData = {
					item: childItem,
					parent: parentData,
					children: null,
					open: false,
					filterState: Visible,
					depth: parentData?.depth + 1 ?? 0,
					element: null,
					name: StringTools.htmlEscape(getName(childItem)),
				};
				childrenData.push(childData);
			}
		}
		if (parentData != null) {
			parentData.children = childrenData;
		}
		return childrenData;
	}

	public function ensureVisible(data) {

	}

	public function rebuildTree() {
		rootData = generateChildren(null);

		queueRefresh(true, true);
	}

	function ensureFlatItemValid() {
		if (flatData != null)
			return;
		flatData = [];
		flattenRec(rootData, flatData);
	}

	var lastHeight = null;

	public function refresh() {
		//itemContainer.innerHTML = "";
		var oldChildren = [for (node in itemContainer.childNodes) node];
		ensureFlatItemValid();

		var itemHeightPx = 20;

		var height = itemHeightPx * flatData.length;
		if (height != lastHeight) {
			itemContainer.style.height = '${height}px';
			lastHeight = height;
		}

		var clipStart = scroll.scrollTop;
		var clipEnd = scroll.getBoundingClientRect().height + clipStart;
		var itemStart = hxd.Math.floor(clipStart / itemHeightPx);
		var itemEnd = hxd.Math.ceil(clipEnd / itemHeightPx);

		for (index in hxd.Math.imax(itemStart, 0) ... hxd.Math.imin(flatData.length, itemEnd + 1)) {
			var data = flatData[index];
			var element = genElement(data);
			element.style.top = '${index * itemHeightPx}px';
			if (!oldChildren.remove(element))
				itemContainer.appendChild(element);
		}

		for (oldChild in oldChildren) {
			itemContainer.removeChild(oldChild);
		}
	}

	static function computeSearchRanges(haystack: String, needle: String) : SearchRanges {
		var pos = haystack.toLowerCase().indexOf(needle);
		if (pos < 0)
			return null;
		return [pos, pos + needle.length];
	}

	public function filterRec(children: Array<TreeItemData2<TreeItem>>) : Bool {
		var anyVisible = false;
		for (child in children) {
			child.filterState = FilterFlags.ofInt(0);
			child.searchRanges = null;

			if (currentSearch.length == 0) {
				child.filterState |= Visible;
			} else {
				child.searchRanges = computeSearchRanges(child.name, currentSearch);
				if (child.searchRanges != null) {
					child.filterState |= MatchSearch;
					child.filterState |= Visible;
				}
			}
			if (child.children == null) {
				generateChildren(child);
			}

			if(filterRec(child.children) && currentSearch.length > 0) {
				child.filterState |= Visible;
				child.filterState |= Open;
			}

			anyVisible = anyVisible || child.filterState.has(Visible);
		}

		if (children == rootData) {
			queueRefresh(true, false);
		}

		return anyVisible;
	}

	function genElement(data: TreeItemData2<TreeItem>) : js.html.Element {
		var element : js.html.Element = data.element;
		if (data.element == null) {
			element = js.Browser.document.createElement("fancy-tree-item");
			element.style.setProperty("--depth", Std.string(data.depth));

			element.innerHTML =
			'
				<fancy-tree-icon class="caret"></fancy-tree-icon>
				<fancy-tree-icon class="header-icon"></fancy-tree-icon>
				<fancy-tree-name></fancy-tree-name>
			';

			var fold = element.querySelector(".caret");
			fold.addEventListener("click", (e) -> {
				toggleDataOpen(data);
				//saveState();
			});

			data.element = element;
		}

		var fold = element.querySelector(".caret");
		fold.classList.toggle("hidden", !hasChildren(data.item));
		element.classList.toggle("open", isOpen(data));

		// function clickHandler(e: js.html.MouseEvent) {
		// 	var lastSelected = currentItem;
		// 	if (!e.ctrlKey) {
		// 		clearSelection();
		// 	}

		// 	var flat = flattenTreeItems();
		// 	var currentIndex = flat.indexOf(currentItem);
		// 	if (e.shiftKey && currentIndex >= 0) {
		// 		var currentIndex = flat.indexOf(currentItem);
		// 		var newIndex = flat.indexOf(data.item);

		// 		var min = hxd.Math.imin(currentIndex, newIndex);
		// 		var max = hxd.Math.imax(currentIndex, newIndex);

		// 		for (i in min...max + 1) {
		// 			setSelection(flat[i], true);
		// 		}
		// 	} else {
		// 		setSelection(data.item, !selection.exists(cast data.item));
		// 	}

		// 	if (!(e.shiftKey && !e.ctrlKey) || currentItem == null)
		// 		setCurrent(data.item);
		// 	onSelectionChanged();
		// }

		var icon = element.querySelector(".header-icon");
		var iconContent = getIcon(data.item);
		icon.classList.toggle("hidden", iconContent == null);
		if (iconContent != null && iconContent != data.iconCache) {
			icon.innerHTML = iconContent;
			data.iconCache = iconContent;
		}

		var nameElement = element.querySelector("fancy-tree-name");
		element.title = data.name;

		if (data.searchRanges != null) {
			var name = data.name;
			var lastPos = 0;
			var finalName = "";
			for (index in 0...(data.searchRanges.length>>1)) {
				var first = name.substr(lastPos, data.searchRanges[0]);
				var match = name.substr(data.searchRanges[0], data.searchRanges[1] - data.searchRanges[0]);
				finalName += first + '<span class="search-hl">' + match + "</span>";
				lastPos = data.searchRanges[1];
			}
			finalName += name.substr(lastPos);
			nameElement.innerHTML = finalName;
		} else {
			nameElement.innerHTML = data.name;
		}


		// if (moveFlags.toInt() != 0) {
		// 	data.header.draggable = true;

		// 	data.header.ondragstart = (e: js.html.DragEvent) -> {
		// 		var draggedPaths = [];
		// 		moveLastDragOver = null;
		// 		if (!selection.get(cast data.item)) {
		// 			clearSelection();
		// 			setSelection(data.item, true);
		// 		}
		// 		for (item in getSelectedItems()) {
		// 			var data = getDataOrRoot(item);
		// 			draggedPaths.push(data.path);
		// 		}
		// 		e.dataTransfer.setData(getDragDataType(), haxe.Json.stringify(draggedPaths));
		// 		trace(e.dataTransfer.types);
		// 		e.dataTransfer.effectAllowed = "move";
		// 		e.dataTransfer.setDragImage(data.header, 0, 0);
		// 	}

		// 	data.header.ondragover = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			var target = getDragTarget(data,e);

		// 			if (canPreformMove(data, target) == null)
		// 				return;

		// 			if (target == In) {
		// 				if (moveLastDragOver == data.item) {
		// 					moveLastDragTime += 1;
		// 				}
		// 				else {
		// 					moveLastDragOver = data.item;
		// 					moveLastDragTime = 0;
		// 				}

		// 				if (moveLastDragTime > 25 && !isDataVisuallyOpen(data)) {
		// 					toggleItemOpen(data.item, true, true, false);
		// 					saveState();
		// 				}
		// 			}

		// 			setDragStyle(data.header, target);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.header.ondragenter = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			var target = getDragTarget(data,e);
		// 			if (canPreformMove(data, target) == null)
		// 				return;
		// 			setDragStyle(data.header, target);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.header.ondragleave = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			setDragStyle(data.header, None);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.header.ondragexit = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			setDragStyle(data.header, None);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.header.ondrop = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			var target = getDragTarget(data,e);
		// 			var moveOp = canPreformMove(data, target);

		// 			setDragStyle(data.header, None);
		// 			e.preventDefault();

		// 			if (moveOp == null)
		// 				return;

		// 			onMove(moveOp.toMove, moveOp.newParent, moveOp.newIndex);
		// 		}
		// 	}
		// }
		//nameElement.onclick = clickHandler;

		return data.element;
	}

	function toggleDataOpen(data: TreeItemData2<TreeItem>, ?force: Bool) {
		var want = force ?? !isOpen(data);
		if (currentSearch.length > 0) {
			data.filterState.setTo(Open, want);
		}
		data.open = want;
		queueRefresh(true, false);
	}

	var refreshQueued = false;
	var flatRebuildQueued = false;
	var searchRebuildQueued = false;

	function queueRefresh(rebuildFlat: Bool, rebuildSearch: Bool) {
		flatRebuildQueued = rebuildFlat;
		searchRebuildQueued = rebuildSearch;
		if (!refreshQueued) {
			refreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onRefresh());
		}
	}

	function onRefresh() {
		if (flatRebuildQueued) {
			flatData = null;
			flatRebuildQueued = false;
		}

		if (searchRebuildQueued) {
			filterRec(rootData);
			searchRebuildQueued = false;
		}

		refresh();
		refreshQueued = false;
	}


	function flattenRec(currentArray: Array<TreeItemData2<TreeItem>>, targetArray: Array<TreeItemData2<TreeItem>>) {
		for (child in currentArray) {
			if (!child.filterState.has(Visible)) continue;
			targetArray.push(child);
			if (isOpen(child)) {
				if (child.children == null)
					generateChildren(child);
				flattenRec(child.children, targetArray);
			}
		}
	}

	function isOpen(data: TreeItemData2<TreeItem>) {
		return data.open || data.filterState.has(Open);
	}


}