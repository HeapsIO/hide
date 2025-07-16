package hide.comp;

enum DropFlag {
	Reorder;
	Reparent;
}

typedef DropFlags = haxe.EnumFlags<DropFlag>;

enum RefreshFlag {
	Flat;
	Search;
	FocusCurrent;
	RegenHeader;
}

typedef RefreshFlags = haxe.EnumFlags<RefreshFlag>;

enum FilterFlag {
	Visible;
	MatchSearch;
	Open;
}

typedef FilterFlags = haxe.EnumFlags<FilterFlag>;

typedef TreeItemData<TreeItem> = {
	element: js.html.Element,
	?searchRanges: FancySearch.SearchRanges,
	item: TreeItem,
	name: String,
	nameCache: String,
	uniqueName: String,
	?iconCache: String,
	filterState: FilterFlags,
	children: Array<TreeItemData<TreeItem>>,
	parent: TreeItemData<TreeItem>,
	depth: Int,
	identifier: String,
	?buttons: Array<{
		element: js.html.Element,
		button: TreeButton<TreeItem>,
		iconCache: String,
	}>,
};

enum DropOperation {
	Before;
	After;
	Inside;
}

typedef TreeButton<TreeItem> = {
	click : (TreeItem) -> Void,

	/**
		Return a html string of the icon content to display in the button.
		Called each time the tree is refreshed.
	**/
	getIcon : (TreeItem) -> String,

	/**
		If set, the function is called to determine if the button should be visible
		event when the item is not hovered
	**/
	?forceVisiblity : (TreeItem) -> Bool,
}

class FancyTree<TreeItem> extends hide.comp.Component {
	var rootData : Array<TreeItemData<TreeItem>> = [];
	var itemMap : Map<{}, TreeItemData<TreeItem>> = [];
	var selection : Map<{}, Bool> = [];
	var openState: Map<String, Bool> = [];
	var currentItem(default, set) : TreeItemData<TreeItem>;
	var currentVisible(default, set) : Bool = false;

	var gotoFileLastTime : Float = 0.0;
	var gotoFileCurrentMatch = "";

	static final gotoFileKeyMaxDelay = 0.5;
	static final overDragOpenDelaySec = 0.5;

	function set_currentVisible(v) {
		currentVisible = v;
		if (currentVisible)
			queueRefresh(FocusCurrent);
		else
			queueRefresh();
		return currentVisible;
	}

	function set_currentItem(v) {
		currentItem = v;
		queueRefresh(FocusCurrent);
		return currentItem;
	}

	var searchBarClosable: hide.comp.FancyClosable = null;
	var searchBar : hide.comp.FancySearch = null;

	var flatData : Array<TreeItemData<TreeItem>>;

	var itemContainer : js.html.Element;
	var scroll : js.html.Element;
	var currentSearch : String = "";

	var moveLastDragOver: TreeItemData<TreeItem>;
	var moveLastDragOverStart: Float = 0;


	public function new(parent: Element, ?saveKey: String) {
		saveDisplayKey = saveKey;
		var el = new Element('
			<fancy-tree tabindex="-1">
				<fancy-closable><fancy-search></fancy-search></fancy-closable>
				<fancy-scroll>
				<fancy-item-container>
				</fancy-item-container>
				</fancy-scroll>
			</fancy-tree>'
		);
		super(parent, el);

		loadState();

		searchBarClosable = new FancyClosable(null, element.find("fancy-closable"));

		searchBar = new FancySearch(null, element.find("fancy-search"));
		searchBar.onSearch = (search, _) -> {
			currentSearch = search.toLowerCase();
			queueRefresh(Search);
		}

		searchBarClosable.onClose = () -> {
			onSearchClose();
		}

		scroll = el.find("fancy-scroll").get(0);
		itemContainer = el.find("fancy-item-container").get(0);
		lastHeight = null;

		var fancyTree = el.get(0);
		fancyTree.onkeydown = inputHandler;
		fancyTree.oncontextmenu = contextMenuHandler.bind(null);

		scroll.onscroll = (e) -> queueRefresh();

		fancyTree.onblur = (e: js.html.FocusEvent) -> {
			if (!fancyTree.contains(cast e.relatedTarget)) {
				currentVisible = false;
				currentItem = null;
			}
		}

		fancyTree.onclick = (e) -> {
			currentVisible = false;
		}

		var resizeObserver = new hide.comp.ResizeObserver((_, _) -> {
			queueRefresh();
		});
		resizeObserver.observe(element.get(0));

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
	public dynamic function onSelectionChanged(enterKey:Bool) {
	}

	/**
		Called when the user double click on an item
	**/
	public dynamic function onDoubleClick(item: TreeItem) {

	}

	public dynamic function getButtons(item: TreeItem) : Array<TreeButton<TreeItem>> {
		return [];
	}

	/**
		Drag and drop interface.
		Set this struct with all of it's function callback to handle drag and drop inside your tree.
	**/
	public var dragAndDropInterface :
	{
		/**
			Called when the user starts a drag and drop operation on `item`.
			Fill dataTransfer with the information you want to transfer, you can use getSelectedItems to handle dragging more than
			one item at a time.
			Return `true` if the drag operation is allowed, and `false` to cancel it
		**/
		onDragStart: (item: TreeItem, dataTransfer: js.html.DataTransfer) -> Bool,

		/**
			Called when the user hovers on `target` with a drag and drop operation. You need to return what drop orperation is allowed
			on the given object
		**/
		getItemDropFlags: (target: TreeItem, dataTransfer: js.html.DataTransfer) -> DropFlags,

		/**
			Called when the user drops an item on `target` and getItemDropFlags returned at least one valid flag.
			`where` tells you where the item was dropped, and you can use `dataTransfer` to know what was dropped
		**/
		onDrop: (target: TreeItem, where: DropOperation, dataTransfer: js.html.DataTransfer) -> Void
	} = null;

	/**
		Called when the user right click an item (or the background) of the tree.
		`item` will be null if the background was clicked. Default is do nothing
	**/
	public dynamic function onContextMenu(item: TreeItem, event : js.html.MouseEvent) {
		event.stopPropagation();
		event.preventDefault();
	}

	// Separate definition to onContextMenu to allow .bind()
	function contextMenuHandler(data: TreeItemData<TreeItem>, event : js.html.MouseEvent) {
		if ((data == null || !selection.exists(cast data)) && !event.shiftKey) {
			clearSelection();
			if (data != null)
				setSelection(data, true);
		}
		onContextMenu(data?.item, event);
	}

	/**
		Called when the user renamed the item via F2 / Context menu
	**/
	public var onNameChange : (item: TreeItem, newName: String) -> Void;

	/**
		Called for each of your items in the tree. for the root elements, get called with null as a parameter
	**/
	public dynamic function getChildren(item: TreeItem) : Array<TreeItem> {return null;}

	/**
		Returns a string that allow an item in the tree to be uniquely identified.
		Default to a path/of/the/item/name
		Customize this if you have items that can share names
	**/
	public dynamic function getIdentifier(item: TreeItem) : String {
		var data = itemMap.get(cast item);
		if (data == null)
			return null;
		function rec(data) {
			if (data.parent != null)
				return getIdentifier(data.parent) + "/" + data.name;
			return data.name;
		}

		return rec(data);
	}

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
		return [for (item => _ in selection) (cast item:TreeItemData<TreeItem>).item];
	}

	public function refreshItem(item: TreeItem) {
		var data = itemMap.get(cast item);
		if (data != null) {
			updateData(data);
			generateChildren(data);
			queueRefresh(Search);
			queueRefresh(RegenHeader);
		}
	}

	function updateData(data : TreeItemData<TreeItem>) {
		data.children = null; // invalidate children if we are regenerating the tree
		data.name = StringTools.htmlEscape(getName(data.item));
		data.identifier = getIdentifier(data.item);
	}

	function generateChildren(parentData: TreeItemData<TreeItem>) : Array<TreeItemData<TreeItem>> {
		var childrenTreeItem = getChildren(parentData?.item);

		var childrenData : Array<TreeItemData<TreeItem>> = [];
		if (childrenTreeItem != null) {
			for (childItem in childrenTreeItem) {
				var childData : TreeItemData<TreeItem> = hrt.tools.MapUtils.getOrPut(itemMap, cast childItem, {
					item: childItem,
					parent: null,
					uniqueName: getUniqueName(childItem),
					filterState: Visible,
					children: null,
					depth: 0,
					element: null,
					name: null,
					identifier: null,
					nameCache: null,
				});
				childData.parent = parentData;
				childData.depth = parentData?.depth + 1 ?? 0;
				updateData(childData);
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
		itemMap.clear();
		rootData = generateChildren(null);
		recLoadChildren(rootData);

		queueRefresh(Search);
	}

	function recLoadChildren(items: Array<TreeItemData<TreeItem>>) {
		for (item in items) {
			if (item.children == null) {
				generateChildren(item);
				recLoadChildren(item.children);
			}
		}
	}

	function regenerateFlatData() {
		flatData = [];
		flattenRec(rootData, flatData);
	}

	public function selectItem(item: TreeItem, openSelf: Bool = false) {
		clearSelection();
		var data = itemMap.get(cast item);
		if (data == null) {
			return;
		}
		setSelection(data, true);
		currentItem = data;
		var cur = openSelf ? data : data.parent;
		while (cur != null) {
			toggleDataOpen(cur, true);
			cur = cur.parent;
		}
		saveState();
	}

	public function rename(item: TreeItem) : Void {
		if (onNameChange == null)
			return;
		var data = itemMap.get(cast item);
		if (data == null)
			return;

		var name = data.element.querySelector("fancy-tree-name");
		//name.innerText = data.name;
		name.contentEditable = "plaintext-only";
		var edit = new ContentEditable(null, new Element(name));

		edit.onChange = (newValue) -> {
			onNameChange(item, name.textContent);
			queueRefresh(RegenHeader);
			element.focus();
		}

		edit.onCancel = () -> {
			queueRefresh(RegenHeader);
			element.focus();
		}

		edit.element.focus();
	}

	function onSearchClose() {
		element.get(0).focus();
		currentSearch = "";

		if (currentItem != null) {
			var cur = currentItem.parent;
			while(cur != null) {
				toggleDataOpen(cur, true);
				cur = cur.parent;
			}
		}
		queueRefresh(Search);
		queueRefresh(FocusCurrent);
	}

	function inputHandler(e: js.html.KeyboardEvent) {
		if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
			e.stopPropagation();
			e.preventDefault();

			searchBarClosable.toggleOpen(true);
			searchBar.focus();
			currentSearch = searchBar.getValue().toLowerCase();
			queueRefresh(Search);
			return;
		}

		if (hide.ui.Keys.matchJsEvent("rename", e, ide.currentConfig) && selection.iterator().hasNext()) {
			e.stopPropagation();
			e.preventDefault();

			if (currentItem != null)
				rename(currentItem.item);
			return;
		}

		if (e.key == "Escape") {
			if (searchBarClosable.isOpen()) {
				e.stopPropagation();
				e.preventDefault();

				searchBarClosable.toggleOpen(false);
				searchBar.blur();

				onSearchClose();
			}
			return;
		}

		if (e.key.length == 1) {
			if (searchBar.hasFocus())
				return;
			e.stopPropagation();
			e.preventDefault();

			var time = haxe.Timer.stamp();
			if (time - gotoFileLastTime > gotoFileKeyMaxDelay) {
				gotoFileCurrentMatch = "";
			}

			gotoFileLastTime = time;

			var lower = e.key.toLowerCase();
			if (lower != gotoFileCurrentMatch) {
				gotoFileCurrentMatch += lower;
			}

			var start = currentItem != null ? flatData.indexOf(currentItem) : 0;
			if (start < 0)
				start = 0;
			for (i in 0 ... flatData.length) {
				var item = flatData[(start + i + 1) % flatData.length];
				if (StringTools.startsWith(item.name.toLowerCase(), gotoFileCurrentMatch)) {
					selectItem(item.item);
					break;
				}
			}
			return;
		}

		var delta = 0;
		switch (e.key) {
			case "ArrowUp":
				delta -= 1;
			case "ArrowDown":
				delta += 1;
			case "PageUp":
				delta -= 10;
			case "PageDown":
				delta += 10;
		}

		if (delta != 0) {
			e.stopPropagation();
			e.preventDefault();
			moveCurrent(delta);
			return;
		}

		if (currentItem == null || searchBar.hasFocus())
			return;

		if (e.key == "ArrowRight" && hasChildren(currentItem.item)) {
			e.stopPropagation();
			e.preventDefault();

			if (currentItem == null || isOpen(currentItem)) {
				moveCurrent(1);
			}
			else if (currentItem != null && !isOpen(currentItem)) {
				toggleDataOpen(currentItem, true);
				saveState();
			}
			return;
		}
		if (e.key == "ArrowLeft") {
			e.stopPropagation();
			e.preventDefault();

			var anyChildren = hasChildren(currentItem.item);
			var goToParent = !anyChildren && currentItem.parent != null;
			goToParent = goToParent || anyChildren && !isOpen(currentItem);

			if (goToParent && currentItem.parent != null) {
				currentItem = currentItem.parent;
			} else if(anyChildren && currentItem != null) {
				toggleDataOpen(currentItem, false);
				saveState();
			}
			return;
		}

		if (e.key == "Enter") {
			e.stopPropagation();
			e.preventDefault();

			clearSelection();
			if (currentItem != null) {
				setSelection(currentItem, true);
			}
			onSelectionChanged(true);
			return;
		}
	}

	public function moveCurrent(delta: Int) {
		if (delta == 0)
			return;
		if (flatData.length <= 0)
			return;

		currentVisible = true;

		var currentIndex = flatData.indexOf(currentItem);
		if (currentIndex < 0) {
			currentItem = flatData[0];

			if (searchBarClosable.isOpen() && searchBar.hasFocus()) {
				searchBar.blur();
				element.focus();
			}
			return;
		}

		var nextIndex = currentIndex + delta;
		if (nextIndex < 0) {
			if (searchBarClosable.isOpen()) {
				searchBar.focus();
				return;
			}
			else {
				nextIndex = 0;
			}
		}
		else {
			if (searchBarClosable.isOpen() && searchBar.hasFocus()) {
				searchBar.blur();
				element.focus();
			}
		}

		if (nextIndex > flatData.length-1)
			nextIndex = flatData.length-1;

		if (nextIndex != currentIndex) {
			currentItem = flatData[nextIndex];
		}
	}

	var lastHeight = null;

	// Never call this function directly, instead call queueRefresh();
	function onRefreshInternal() {
		if (currentRefreshFlags.has(Search)) {
			filterRec(rootData);
			currentRefreshFlags.set(Flat);
		}

		if (currentRefreshFlags.has(Flat) || flatData == null) {
			regenerateFlatData();
		}

		//itemContainer.innerHTML = "";
		var oldChildren = [for (node in itemContainer.childNodes) node];

		var itemHeightPx = 20;

		var height = itemHeightPx * flatData.length;
		if (height != lastHeight) {
			itemContainer.style.height = '${height}px';
			lastHeight = height;
		}

		var scrollHeight = scroll.getBoundingClientRect().height;

		if (currentRefreshFlags.has(FocusCurrent)) {
			var currentIndex = flatData.indexOf(currentItem);

			if (currentIndex >= 0) {
				var currentHeight = currentIndex * itemHeightPx;
				if (currentHeight < scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight);
				}

				if (currentHeight + itemHeightPx - scrollHeight > scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight + itemHeightPx - scrollHeight);
				}
			}
		}

		var clipStart = scroll.scrollTop;
		var clipEnd = scrollHeight + clipStart;
		var itemStart = hxd.Math.floor(clipStart / itemHeightPx);
		var itemEnd = hxd.Math.ceil(clipEnd / itemHeightPx);

		for (index in hxd.Math.imax(itemStart, 0) ... hxd.Math.imin(flatData.length, itemEnd + 1)) {
			var data = flatData[index];
			var element = genElement(data);
			element.style.transform = 'translate(0, ${index * itemHeightPx}px)';
			if (!oldChildren.remove(element))
				itemContainer.appendChild(element);
		}

		for (oldChild in oldChildren) {
			if (itemContainer.contains(oldChild))
				itemContainer.removeChild(oldChild);
		}

		currentRefreshFlags = RefreshFlags.ofInt(0);
		refreshQueued = false;
	}

	public function invalidateChildren(item: TreeItem) {
		var data = itemMap.get(cast item);
		if (data == null)
			return;
		data.children = null;
		queueRefresh(Search);
	}

	public function filterRec(children: Array<TreeItemData<TreeItem>>, parentMatch: Bool = false) : Bool {
		var anyVisible = false;
		var searchQuery = FancySearch.createSearchQuery(currentSearch);
		for (child in children) {


			child.filterState = FilterFlags.ofInt(0);
			child.searchRanges = null;

			if (child.children == null) {
				generateChildren(child);
			}

			if (parentMatch) {
				child.filterState |= Visible;
			}

			if (currentSearch.length == 0) {
				child.filterState |= Visible;
			} else {
				child.searchRanges = FancySearch.computeSearchRanges(child.name, searchQuery);
				if (child.searchRanges != null) {
					child.filterState |= MatchSearch;
					child.filterState |= Visible;
					child.filterState |= Open;
				}
			}

			parentMatch = child.filterState.has(MatchSearch);

			if(filterRec(child.children, parentMatch) && currentSearch.length > 0) {
				child.filterState |= Visible;
				child.filterState |= Open;
			}

			anyVisible = anyVisible || child.filterState.has(Visible);
		}

		return anyVisible;
	}

	function genElement(data: TreeItemData<TreeItem>) : js.html.Element {
		var element : js.html.Element = data.element;

		if (currentRefreshFlags.has(RegenHeader) && data.element != null) {
			data.element.remove();
			data.element = null;
			data.buttons = null;
		}

		if (data.element == null) {
			element = js.Browser.document.createElement("fancy-tree-item");
			element.style.setProperty("--depth", Std.string(data.depth));
			data.iconCache = null;
			data.nameCache = null;

			element.innerHTML =
			'
				<fancy-tree-icon class="caret"></fancy-tree-icon>
				<fancy-tree-icon class="header-icon"></fancy-tree-icon>
				<fancy-tree-name></fancy-tree-name>
				<fancy-flex-fill></fancy-flex-fill>
			';

			var fold = element.querySelector(".caret");
			fold.addEventListener("click", (e) -> {
				toggleDataOpen(data);
				saveState();
				e.stopPropagation();
			});

			element.onclick = dataClickHandler.bind(data);
			element.oncontextmenu = contextMenuHandler.bind(data);
			element.ondblclick = doubleClickHander.bind(data);

			data.element = element;

			var buttons = getButtons(data.item);
			data.buttons = [];
			for (buttonData in buttons) {
				var button = {
					element: js.Browser.document.createElement("fancy-button"),
					button: buttonData,
					iconCache: null,
				};
				data.buttons.push(button);

				button.element.classList.add("quieter");

				button.element.onclick = (e: js.html.MouseEvent) -> {
					e.stopPropagation();
					button.button.click(data.item);
					queueRefresh();
				};

				button.element.ondblclick = (e: js.html.MouseEvent) -> {
					e.stopPropagation();
				};

				element.appendChild(button.element);
			}

			setupDragAndDrop(data);
		}

		var fold = element.querySelector(".caret");
		fold.classList.toggle("hidden", !hasChildren(data.item));
		element.classList.toggle("open", isOpen(data));
		element.classList.toggle("selected", selection.exists(cast data));
		element.classList.toggle("current", currentVisible && currentItem == data);

		var icon = element.querySelector(".header-icon");
		var iconContent = getIcon(data.item);
		icon.classList.toggle("button-hidden", iconContent == null);
		if (iconContent != null && iconContent != data.iconCache) {
			icon.innerHTML = iconContent;
			data.iconCache = iconContent;
		}

		var nameElement = element.querySelector("fancy-tree-name");
		element.title = data.name;

		var wantedName = if (data.searchRanges != null) {
			hide.comp.FancySearch.splitSearchRanges(data.name, data.searchRanges);
		} else {
			data.name;
		}
		if (wantedName != data.nameCache) {
			data.nameCache = wantedName;
			nameElement.innerHTML = wantedName;
		}

		for (button in data.buttons) {
			var icon = button.button.getIcon(data.item);
			if (icon != button.iconCache && icon != null) {
				button.element.innerHTML = icon;
				button.iconCache = icon;
			}
			button.element.classList.toggle("hidden", button.button.forceVisiblity == null || !button.button.forceVisiblity(data.item));
		}

		return data.element;
	}

	function setupDragAndDrop(data: TreeItemData<TreeItem>) {
		if (dragAndDropInterface != null) {
			var ondragstart = (e: js.html.DragEvent) -> {
				if (!selection.get(cast data)) {
					clearSelection();
					setSelection(data, true);
				}

				moveLastDragOver = null;

				if (dragAndDropInterface.onDragStart(data.item, e.dataTransfer)) {
					e.dataTransfer.effectAllowed = "move";
					e.dataTransfer.setDragImage(data.element, 0, 0);
				} else {
					e.preventDefault();
				}
			};

			var elements = [data.element.querySelector("fancy-tree-name"), data.element.querySelector(".header-icon")];

			// drag from the interactible elements of the item
			for (element in elements) {
				element.draggable = true;
				element.ondragstart = ondragstart;
			}


			// drop on the full item element
			data.element.ondragover = (e: js.html.DragEvent) -> {
				var operation = getDragOperation(data,e);
				if (operation != null) {
					// Auto open item if the user hover for enough time
					if (operation == Inside) {
						var time = haxe.Timer.stamp();

						if (moveLastDragOver != data) {
							moveLastDragOver = data;
							moveLastDragOverStart = haxe.Timer.stamp();
						}

						if (time - moveLastDragOverStart > overDragOpenDelaySec && !isOpen(data)) {
							toggleDataOpen(data, true);
							saveState();
						}
					}

					e.preventDefault();
					setDragStyle(data.element, operation);
				} else {
					setDragStyle(data.element, null);
				}
			}

			data.element.ondragenter = (e: js.html.DragEvent) -> {
				var operation = getDragOperation(data,e);
				if (operation != null) {
					setDragStyle(data.element, operation);
					e.preventDefault();
				}
			}

			data.element.ondragleave = (e: js.html.DragEvent) -> {
				setDragStyle(data.element, null);
				e.preventDefault();
			}

			data.element.ondrop = (e: js.html.DragEvent) -> {
				setDragStyle(data.element, null);
				e.preventDefault();

				var operation = getDragOperation(data,e);
				if (operation != null) {
					dragAndDropInterface.onDrop(data.item, operation, e.dataTransfer);
				}
				e.preventDefault();
				e.stopPropagation();
			}
		}
	}

	function setDragStyle(element: js.html.Element, target: Null<DropOperation>) {
		element.classList.toggle("feedback-drop-top", target == Before);
		element.classList.toggle("feedback-drop-bot", target == After);
		element.classList.toggle("feedback-drop-in", target == Inside);
	}

	function getDragOperation(data: TreeItemData<TreeItem>, event: js.html.DragEvent) : DropOperation {
		var element = data.element;
		var flags = dragAndDropInterface.getItemDropFlags(data.item, event.dataTransfer);
		if (flags == DropFlags.ofInt(0)) {
			return null;
		}

		if (!flags.has(Reorder)) {
			return Inside;
		}

		var rect = element.getBoundingClientRect();
		var nameRect = element.getBoundingClientRect();

		if (flags.has(Reparent) && event.clientX > nameRect.left + 100) {
			return Inside;
		}

		if (event.clientY > rect.top + rect.height / 2) {
			return After;
		}
		return Before;
	}

	public function clearSelection() {
		selection.clear();
		queueRefresh();
	}



	function setSelection(data: TreeItemData<TreeItem>, select: Bool) {
		if (data == null)
			return;

		if (select) {
			selection.set(cast data, true);
		} else {
			selection.remove(cast data);
		}
	}

	function doubleClickHander(data: TreeItemData<TreeItem>, event: js.html.MouseEvent) : Void {
		onDoubleClick(data.item);
	}

	function dataClickHandler(data: TreeItemData<TreeItem>, event: js.html.MouseEvent) : Void {
		if (!event.ctrlKey) {
			clearSelection();
		}

		var currentIndex = flatData.indexOf(currentItem);
		if (event.shiftKey && currentIndex >= 0) {
			var newIndex = flatData.indexOf(data);

			var min = hxd.Math.imin(currentIndex, newIndex);
			var max = hxd.Math.imax(currentIndex, newIndex);

			for (i in min...max + 1) {
				setSelection(flatData[i], true);
			}
		} else {
			setSelection(data, !selection.exists(cast data));
		}

		if (!(event.shiftKey && !event.ctrlKey) || currentItem == null)
			currentItem = data;
		onSelectionChanged(false);

		queueRefresh();
	}

	public function openItem(item: TreeItem, ?force: Bool) {
		var data = itemMap.get(cast item);
		if (data != null) {
			toggleDataOpen(data, force);
			saveState();
		}
	}

	public function collapseItem(item: TreeItem) {
		var data = itemMap.get(cast item);
		if (data == null)
			return;

		function collapseData(data: TreeItemData<TreeItem>) {
			toggleDataOpen(data, false);
			for (child in data.children) {
				collapseData(child);
			}
		}

		collapseData(data);
		saveState();
	}

	function childOf(child: TreeItemData<TreeItem>, parent: TreeItemData<TreeItem>) {
		var current = child;
		while (current != null) {
			if (current == parent) {
				return true;
			}
		}
		return false;
	}

	function toggleDataOpen(data: TreeItemData<TreeItem>, ?force: Bool) {
		var want = force ?? !isOpen(data);
		if (currentSearch.length > 0) {
			data.filterState.setTo(Open, want);
		}

		if (want) {
			openState.set(data.uniqueName, true);
		} else {
			openState.remove(data.uniqueName);
		}
		queueRefresh(Flat);
	}

	function loadState() {
		var open : Array<String> = getDisplayState("openState");
		if (open != null) {
			openState = [];
			for (item in open) {
				openState.set(item, true);
			}
		}
	}

	function saveState() {
		var ser = [for (k => _ in openState) k];
		saveDisplayState("openState", ser);
	}

	var refreshQueued : Bool = false;
	var currentRefreshFlags : RefreshFlags = RefreshFlags.ofInt(0);


	// TODO(ces) : The main release of haxe doesn't support type inference with `|` which make using
	// queueRefresh with an EnumFlag as an argument cumbersome. Untill then, make multiple queueRefresh calls
	// with each of the flags you want to set
	public function queueRefresh(?flag: RefreshFlag = null) {
		if (flag != null) {
			currentRefreshFlags.set(flag);
		}
		if (!refreshQueued) {
			refreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onRefreshInternal());
		}
	}

	public static function animateReveal(element: js.html.Element, reveal: Bool, durationMs: Int = 75) {
		function finish() {
			if (reveal) {
				element.style.height = "auto";
			} else {
				element.style.height = null;
			}
		};
		for (anim in element.getAnimations()) {
			anim.cancel();
		}

		if (durationMs > 0) {
			var anim = element.animate([
				{height: "0px"},
				{height: '${element.scrollHeight}px'},
			], {
				duration: durationMs,
				iterations: 1,
				direction: reveal ? js.html.PlaybackDirection.NORMAL : js.html.PlaybackDirection.REVERSE,
				easing: "ease-in",
			});

			anim.onfinish = (e) -> finish();
		}
		else {
			finish();
		}
	}
	function flattenRec(currentArray: Array<TreeItemData<TreeItem>>, targetArray: Array<TreeItemData<TreeItem>>) {
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

	function isOpen(data: TreeItemData<TreeItem>) {
		// // Always open folders that have selected children
		// for (selected => _ in selection) {
		// 	var cur = (cast selected:TreeItemData<TreeItem>).parent;
		// 	while (cur != null) {
		// 		if (data == cur)
		// 			return true;
		// 		cur = cur.parent;
		// 	}
		// }

		return (openState.get(data.uniqueName) ?? false) || data.filterState.has(Open);
	}

}