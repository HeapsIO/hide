package hrt.ui;
import hrt.ui.HuiTreeLine;

#if hui

enum DropFlag {
	Reorder;
	Reparent;
}

typedef DropFlags = haxe.EnumFlags<DropFlag>;

enum DropOperation {
	Before;
	After;
	Inside;
}

enum RefreshFlag {
	Refresh;
	RegenerateFlatten;
	RootData;
}

typedef RefreshFlags = haxe.EnumFlags<RefreshFlag>;

enum FilterFlag {
	Visible;
	MatchSearch;
	Open; // the item contains items that matches the search
}

typedef FilterFlags = haxe.EnumFlags<FilterFlag>;

typedef TreeItemData = {
	item: Any,
	line: HuiTreeLine,
	parent: TreeItemData,
	children: Array<TreeItemData>,
	name: String,
	icon: hxd.res.Image,
	depth: Int,
	filterState: FilterFlags,
	identifier: String,
	?searchRanges: hide.Search.SearchRanges,
}

typedef SelectionRange = {start: Int, length: Int};

class HuiTree<TreeItem> extends HuiElement {
	static var SRC =
		<hui-tree>
			<hui-element id="search-bar-container">
				<hui-input-box id="search-bar" class="search"/>
				<hui-button class="small-square quiet" id="search-bar-close"><hui-icon("close")/></hui-button>
			</hui-element>
			<hui-element id="wrapper">
				<hui-virtual-list id="list"/>
			</hui-element>
		</hui-tree>

	var rootData: Array<TreeItemData> = [];
	var flatList: Array<TreeItemData> = [];
	var keyboardFocus: TreeItemData = null;

	/**TreeItem -> Bool map**/
	var selectedElements: Map<{}, Bool> = [];
	var lastSelectedElement: TreeItemData = null;

	var renamedElement: {item: TreeItem, callback: (String) -> Void, selectionRange: SelectionRange};

	/**TreeItem -> TreeItemData map**/
	var itemMap : Map<{}, TreeItemData> = [];

	/**Identifier to item open state (item if considered closed if no entry exist in the map)**/
	var openState: Map<String, Bool> = [];

	var afterRefreshCallbacks: Array<Void -> Void> = [];

	var refreshFlags : RefreshFlags = RefreshFlags.ofInt(0);

	public function new(?parent) {
		super(parent);
		initComponent();

		list.generateItem = generateItem;
		list.refreshItem = cast refreshItem;
		requestRefresh(RegenerateFlatten);
		requestRefresh(RootData);

		searchBarContainer.visible = false;

		registerCommand(HuiCommands.search,  ElementAndChildren, () -> {
			openSearch();
		});

		searchBar.onBeforeKeyDown = keyDownHandler.bind(true);
		searchBar.onChange = (tmp) -> {
			keyboardFocus = null;
			requestRefresh(RegenerateFlatten);
		}
		searchBarClose.onClick = (e) -> {
			closeSearch();
		}

		onKeyDown = keyDownHandler.bind(false);

		onPush = (e:hxd.Event) -> {
			if (e.button == 0 || e.button == 1) {
				//interactive.focus();
				e.propagate = false;

				if (!hxd.Key.isDown(hxd.Key.CTRL)) {
					selectedElements.clear();
					lastSelectedElement = null;
					keyboardFocus = null;
					userSelectionChanged();
				}

				if (e.button == 1) {
					onItemContextMenu(null);
				}
			}
		}
	}

	override function onFocusLostInternal(e:hxd.Event) {
		super.onFocusLostInternal(e);
		keyboardFocus = null;
		refreshInternal();
	}

	function closeSearch() {
		searchBar.textInput.blur();
		searchBarContainer.visible = false;
		requestRefresh(RegenerateFlatten);
	}

	function keyDownHandler(isSearchBar: Bool, e: hxd.Event) {
		// we need to do this because e.cancel = true will make the event propagate even
		// if e.propagate is false, and we need the e.cancel = true to override the search bar
		// default behavior
		if (!isSearchBar && searchBar.textInput.hasFocus())
			return;

		if (e.keyCode == hxd.Key.ESCAPE) {
			if (searchBarContainer.visible) {
				closeSearch();
				e.propagate = false;
			}
		}
		if (e.keyCode == hxd.Key.UP) {
			focusMove(-1);
			e.propagate = false;
		} else if (e.keyCode == hxd.Key.DOWN) {
			focusMove(1);
			searchBar.preventDefault = true;
			e.propagate = false;
		} else if (e.keyCode == hxd.Key.RIGHT) {
			if (keyboardFocus != null) {
				if (!isOpen(keyboardFocus)) {
					toggleItemDataOpen(keyboardFocus, true);
				} else if (keyboardFocus.children?.length > 0) {
					focusSetInternal(keyboardFocus.children[0]);
				}
				e.propagate = false;
				searchBar.preventDefault = true;
			}
		} else if (e.keyCode == hxd.Key.LEFT) {
			if (keyboardFocus != null) {
				if (!isOpen(keyboardFocus)) {
					if (keyboardFocus.parent != null) {
						focusSetInternal(keyboardFocus.parent);
					}
				} else {
					toggleItemDataOpen(keyboardFocus, false);
				}
				searchBar.preventDefault = true;
				e.propagate = false;
			}
		} else if (e.keyCode == hxd.Key.ENTER) {
			if (keyboardFocus != null) {
				onItemDoubleClick(e, keyboardFocus.item);
			}
			searchBar.preventDefault = true;
			e.propagate = false;
		}
	}

	public function getLastFocusItem() : TreeItem {
		if (selectedElements.get(lastSelectedElement) != null) {
			return lastSelectedElement.item;
		}
		return null;
	}
	public function openSearch() {
		searchBarContainer.visible = true;
		@:privateAccess searchBar.textInput.focus();
	}

	/**
		Request to rebuild an item in the tree
	**/
	public function rebuild(item: TreeItem = null) {
		if (item != null) {
			var data = itemMap.get(cast item);
			if(data != null)
				updateData(data);
			requestRefresh(RegenerateFlatten);
			return;
		} else {
			requestRefresh(RootData);
		}
	}

	function requestRefresh(refreshFlag: RefreshFlag = RefreshFlag.Refresh) {
		refreshFlags.set(refreshFlag);
	}

	public function focusSet(newFocus: TreeItem) : Void {
		focusSetInternal(itemMap.get(cast newFocus));
	}

	function focusSetInternal(newFocus: TreeItemData) : Void {
		keyboardFocus = newFocus;
		if (keyboardFocus != null) {
			list.scrollTo(keyboardFocus);
			if (!hxd.Key.isDown(hxd.Key.SHIFT))
				selectedElements.clear();
			selectedElements.set(cast keyboardFocus.item, true);
			onUserSelectionChanged();
		}
	}

	public function focusMove(offset: Int) : Void {
		var id = flatList.indexOf(keyboardFocus);
		if (id == -1) {
			id = flatList.indexOf(lastSelectedElement);
		}
		if (id < 0) {
			if (offset < 0) {
				id = flatList.length;
			} else {
				id = 0;
			}
		} else {
			id = (id + offset + flatList.length) % flatList.length;
		}
		focusSetInternal(flatList[id]);
	}

	/**
		Return true if the rename operation was started, false if not
	**/
	public function rename(item: TreeItem, callback: (newName: String) -> Void, ?selectionRange: SelectionRange) {
		renamedElement = {
			item: item,
			callback: callback,
			selectionRange: selectionRange,
		};
		revealItem(cast item);
		requestRefresh();
	}

	/**
		Called for each of your items in the tree. for the root elements, get called with null as a parameter
	**/
	public dynamic function getItemChildren(item: TreeItem) : Array<TreeItem> {return null;}

	/**
		Called to know if an item in the tree can be opened or has children. Default to calling getChildren and seeing if it returns false.
		Set this function to optimise the initial loading of the tree if getChildren is expensive
	**/
	public dynamic function hasChildren(item : TreeItem) : Bool {
		var children = getItemChildren(item);
		if (children == null)
			return false;
		return children.length > 0;
	}

	/**
		Returns a string that allow an item in the tree to be uniquely identified.
		Default to a path/of/the/item/name
		Customize this if you have items that can share names
	**/
	public dynamic function getIdentifier(item: TreeItem) : String {
		var data = itemMap.get(cast item);
		if (data == null)
			return null;
		function rec(data : TreeItemData) {
			if (data.parent != null)
				return getIdentifier(cast data.parent.item) + "/" + data.name;
			return data.name;
		}

		return rec(data);
	}

	/**
		Called for each of your items in the tree. Allow custom style on tree elements
	**/
	public dynamic function applyTreeStyle(item: TreeItem, element : HuiTreeLine) {
	}

	public function toggleItemOpen(item: TreeItem, ?force: Bool) {
		var data = itemMap.get(cast item);
		if (data == null)
			return;
		toggleItemDataOpen(data, force);
	}

	/** Open all of item parents so that item becomes visible in the tree **/
	public function revealItem(item: TreeItem) : Void {
		if (refreshFlags.toInt() != 0) {
			afterRefreshCallbacks.push(revealItem.bind(item));
			return;
		}

		function rec(data: TreeItemData) {
			if (data == null)
				return;
			toggleItemDataOpen(data, true);
			rec(data.parent);
		}

		rec(itemMap.get(cast item)?.parent);
	}

	public function revealAll() : Void {
		if (refreshFlags.toInt() != 0) {
			afterRefreshCallbacks.push(revealAll);
			return;
		}

		for (data in itemMap) {
			toggleItemDataOpen(data, true);
		}
	}

	public function closeAll() : Void {
		if (refreshFlags.toInt() != 0) {
			afterRefreshCallbacks.push(revealAll);
			return;
		}

		for (data in itemMap) {
			toggleItemDataOpen(data, false);
		}
	}

	public dynamic function getItemName(item: TreeItem) : String {
		return "";
	}

	public dynamic function getItemIcon(item: TreeItem) : hxd.res.Image {
		return HuiRes.ui.icons.file_blank;
	}

	public dynamic function onItemContextMenu(item: TreeItem) : Void {

	}

	/**Note : also called when the user press enter on this item using the keyboard**/
	public dynamic function onItemDoubleClick(e: hxd.Event, item: TreeItem) : Void {

	}

	/**
		Called every time the selection changed by an action from the user
	**/
	public dynamic function onUserSelectionChanged() : Void {

	}

	function userSelectionChanged() : Void {
		requestRefresh();
		onUserSelectionChanged();
	}

	/**
		Replace the current selected elements in the tree with selection.
		Does not call onUserSelectionChanged
	**/
	public function setSelection(selection: Array<TreeItem>) : Void {
		selectedElements.clear();
		for (item in selection) {
			selectedElements.set(cast item, true);
			revealItem(cast item);
		}
		requestRefresh();
	}

	public function getSelectedItems() : Array<TreeItem> {
		return [for (item => _ in selectedElements) cast item];
	}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);

		refreshInternal();
	}

	function refreshInternal() {
		var iterCount = 0;
		while (refreshFlags.toInt() != 0 && iterCount < 2) {
			if (refreshFlags.has(RootData)) {
				rootData = generateChildren(null);
				refreshFlags.set(RegenerateFlatten);
			}

			if (refreshFlags.has(RegenerateFlatten)) {
				flatten();
				list.setItems(flatList);
			}

			list.refresh();

			refreshFlags = RefreshFlags.ofInt(0);

			var callbacks = afterRefreshCallbacks.copy();
			afterRefreshCallbacks = [];
			for (callback in callbacks) {
				callback();
			}
			iterCount++;
		}
		if (refreshFlags.toInt() != 0) {
			throw "afterRefreshCallback loop detected !";
		}
	}

	function refreshSync() {
		refreshFlags.set(RootData);
		refreshInternal();
		list.refresh();
		@:privateAccess list.refreshInternal();
	}

	function generateItem(data: TreeItemData) : HuiElement {
		var line = new HuiTreeLine(data, this);

		line.onCaretClick = () -> {
			toggleItemDataOpen(data);
		}

		line.onItemSelect = (shift, ctrl) -> {
			if (!ctrl) {
				selectedElements.clear();
			}

			if (shift && lastSelectedElement != null) {
				var idx = flatList.indexOf(lastSelectedElement);
				var ourIndex = flatList.indexOf(data);
				var min = hxd.Math.imin(idx, ourIndex);
				var max = hxd.Math.imax(idx, ourIndex);

				if (min >= 0) {
					for (i in min...max+1) {
						selectedElements.set(cast flatList[i].item, true);
					}
				}
			} else {
				selectedElements.set(cast data.item, true);
				lastSelectedElement = data;
			}
			userSelectionChanged();
		}

		line.onContextMenu = () -> {
			onItemContextMenu(data.item);
		}

		if (dragAndDropInterface != null) {
			line.onDragStart = () -> {
				dragAndDropInterface.onDragStart(data.item);
			}

			line.onDrop = (op: HuiDragOp) -> {
				dragAndDropInterface.onDrop(data.item, line.getDropOperation(op), op);
			}


			line.onDragOver = line.onDragMove = (op) -> {
				var dropOp = line.getDropOperation(op);

				op.acceptDrop = dropOp != null;

				line.dom.toggleClass("drop-before", dropOp==Before);
				line.dom.toggleClass("drop-inside", dropOp==Inside);
				line.dom.toggleClass("drop-after", dropOp==After);
			}

			line.onDragOut = (e) -> {
				line.dom.removeClass("drop-before");
				line.dom.removeClass("drop-inside");
				line.dom.removeClass("drop-after");
			}
		}

		line.onDoubleClick = (e) -> {
			onItemDoubleClick(e, data.item);
		}
		return line;
	}

	function toggleItemDataOpen(data: TreeItemData, ?force : Bool) : Void {
		if (!hasChildren(cast data.item))
			return;
		var currentState = isOpen(data);
		var newState = force ?? !currentState;
		if (currentState == newState)
			return;

		if (newState) {
			generateChildren(data);
			openState.set(data.identifier, true);
		} else {
			openState.remove(data.identifier);
		}
		saveOpenState();
		refreshFlags.set(RegenerateFlatten);
	}

	function saveOpenState() {
		if (saveDisplayKey == null)
			return;

		var save: Array<String> = [];

		var allId: Map<String, Bool> = [];
		for (item in itemMap) {
			allId.set(item.identifier, true);
		}

		for (k => v in openState) {
			if (allId.exists(k))
				save.push(k);
		}

		saveDisplayState("openState", save);
	}

	override function onLoadState() {
		super.onLoadState();

		var save : Array<String> = getDisplayState("openState", []);
		for (k in save) {
			openState.set(k, true);
		}
	}

	function refreshItem(item: TreeItemData, element: HuiTreeLine) : Void {
		element?.refresh();
		applyTreeStyle(item.item, element);
	}

	function forceRefreshTree() {
		for (data in itemMap) {
			data.children = null;
		}
		rootData = generateChildren(null);
		requestRefresh();
	}

	function generateChildren(parent: TreeItemData) : Array<TreeItemData> {
		var childrenItems = getItemChildren(cast parent?.item);

		var childrenData : Array<TreeItemData> = [];
		if (childrenItems != null) {
			for (childItem in childrenItems) {
				var childData : TreeItemData = hrt.tools.MapUtils.getOrPut(itemMap, cast childItem, {
					item: childItem,
					parent: null,
					// uniqueName: getUniqueName(childItem),
					filterState: Visible,
					children: null,
					depth: 0,
					line: null,
					name: null,
					icon: null,
					identifier: null,
				});

				childData.parent = parent;
				if (parent != null) {
					childData.depth = parent.depth + 1;
				} else {
					childData.depth = 0;
				}
				updateData(childData);
				childrenData.push(childData);
			}
		}

		if (parent != null) {
			parent.children = childrenData;
		}
		return childrenData;
	}

	/**
		Drag and drop interface.
		Set this struct with all of it's function callback to handle drag and drop inside your tree.
	**/
	public var dragAndDropInterface :
	{
		/**
			Called when the user starts a drag and drop operation on `item`.
			Call startDrag with your data to initiate the drag
		**/
		onDragStart: (item: TreeItem) -> Void,

		/**
			Called when the user hovers on `target` with a drag and drop operation. You need to return what drop operation is allowed
			on the given object
		**/
		getItemDropFlags: (target: TreeItem, op : HuiDragOp) -> DropFlags,

		/**
			Called when the user drops an item on `target` and getItemDropFlags returned at least one valid flag.
			`where` tells you where the item was dropped
		**/
		onDrop: (target: TreeItem, where: DropOperation, op : HuiDragOp) -> Void
	} = null;

	function updateData(data: TreeItemData) {
		data.children = null; // invalidate children if we are regenerating the tree
		data.name = StringTools.htmlEscape(getItemName(cast data.item));
		data.icon = getItemIcon(cast data.item);
		data.identifier = getIdentifier(cast data.item);
	}

	function flatten() {

		if (searchBarContainer.visible) {
			var currentSearch = searchBar.text;
			var searchQuery = hide.Search.createSearchQuery(searchBar.text.toLowerCase());
			function filterRec(children: Array<TreeItemData>, parentMatch: Bool = false) : Bool {
				var anyVisible = false;
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
						child.searchRanges = hide.Search.computeSearchRanges(child.name, searchQuery);
						if (child.searchRanges != null) {
							child.filterState |= MatchSearch;
							child.filterState |= Visible;
							child.filterState |= Open;
						}
					}

					if(filterRec(child.children, child.filterState.has(MatchSearch)) && currentSearch.length > 0) {
						child.filterState |= Visible;
						child.filterState |= Open;
					}

					anyVisible = anyVisible || child.filterState.has(Visible);
				}

				return anyVisible;
			}

			filterRec(rootData);
		}

		flatList.resize(0);

		function rec(items: Array<TreeItemData>) {
			for (item in items) {
				if (searchBarContainer.visible && !item.filterState.has(Visible)) continue;
				flatList.push(item);
				if (item.children == null) {
					generateChildren(item);
				}
				if (isOpen(item))
					rec(item.children);
			}
		}
		rec(rootData);
	}

	function isOpen(data: TreeItemData) : Bool {
		return data.children?.length > 0 && ((openState.get(data.identifier) ?? false) || data.filterState.has(Open));
	}

	function isSelected(data: TreeItemData) : Bool {
		return selectedElements.get(cast data.item) == true;
	}

	public function isItemSelected(data: TreeItem) : Bool {
		return isSelected(itemMap.get(cast data));
	}

	public function isItemOpen(data: TreeItem) : Bool {
		var data = itemMap.get(cast data);
		if (data == null)
			return false;
		return isOpen(data);
	}
}

#end