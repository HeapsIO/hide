package hrt.ui;
import hrt.ui.HuiTreeLine;

#if hui

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
	depth: Int,
	filterState: FilterFlags,
	identifier: String,
}

class HuiTree<TreeItem> extends HuiElement {
	static var SRC =
		<hui-tree>
			<hui-virtual-list id="list"/>
		</hui-tree>

	var rootData: Array<TreeItemData> = [];
	var flatList: Array<TreeItemData> = [];
	var keyboardFocus: TreeItemData = null;

	var selectedElements: Map<{}, Bool> = [];
	var lastSelectedElement: TreeItemData = null;

	/**TreeItem -> TreeItemData map**/
	var itemMap : Map<{}, TreeItemData> = [];

	/**Identifier to item open state (item if considered closed if no entry exist in the map)**/
	var openState: Map<String, Bool> = [];


	var refreshFlags : RefreshFlags = RefreshFlags.ofInt(0);

	public function new(?parent) {
		super(parent);
		initComponent();

		list.generateItem = generateItem;
		list.refreshItem = cast refreshItem;
		requestRefresh(RegenerateFlatten);
		requestRefresh(RootData);

		onKeyDown = (e:hxd.Event) -> {
			if (e.keyCode == hxd.Key.UP) {
				focusMove(-1);
				e.propagate = false;
			} else if (e.keyCode == hxd.Key.DOWN) {
				focusMove(1);
				e.propagate = false;
			} else if (e.keyCode == hxd.Key.RIGHT) {

				if (keyboardFocus != null) {
					if (!isOpen(keyboardFocus)) {
						toggleItemOpen(keyboardFocus, true);
					} else if (keyboardFocus.children?.length > 0) {
						focusSetInternal(keyboardFocus.children[0]);
					}
					e.propagate = false;
				}
			} else if (e.keyCode == hxd.Key.LEFT) {
				if (keyboardFocus != null) {
					if (!isOpen(keyboardFocus)) {
						if (keyboardFocus.parent != null) {
							focusSetInternal(keyboardFocus.parent);
						}
					} else {
						toggleItemOpen(keyboardFocus, false);
					}
					e.propagate = false;
				}
			}
		}

		onPush = (e:hxd.Event) -> {
			if (e.button == 0) {
				interactive.focus();
				e.propagate = false;

				if (!hxd.Key.isDown(hxd.Key.CTRL)) {
					selectedElements.clear();
					userSelectionChanged();
				}
			}
		}
	}

	/**
		Request to rebuild an item in the tree
	**/
	public function rebuild(item: TreeItem = null) {
		if (item != null) {
			var data = itemMap.get(cast item);
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
		}
	}

	public function focusMove(offset: Int) : Void {
		var id = flatList.indexOf(keyboardFocus);
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

	public dynamic function getItemName(item: TreeItem) : String {
		return "";
	}

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
			var data = itemMap.get(cast item);
			if (data == null) {
				selectedElements.set(cast item, true);
			}
		}
		requestRefresh();
	}

	public function getSelectedItems() : Array<TreeItem> {
		return [for (item => _ in selectedElements) (cast item:TreeItemData).item];
	}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);

		if (refreshFlags.toInt() != 0) {
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
		}
	}

	function generateItem(data: TreeItemData) : HuiElement {
		var line = new HuiTreeLine(data, this);

		line.onCaretClick = () -> {
			toggleItemOpen(data);
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
						selectedElements.set(cast flatList[i], true);
					}
				}
			} else {
				selectedElements.set(cast data, true);
				lastSelectedElement = data;
			}
			userSelectionChanged();
		}

		line.onDoubleClick = (e) -> {
			onItemDoubleClick(e, data.item);
		}
		return line;
	}

	function toggleItemOpen(data: TreeItemData, ?force : Bool) : Void {
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
		refreshFlags.set(RegenerateFlatten);

	}

	function refreshItem(item: TreeItemData, element: HuiTreeLine) : Void {
		element?.refresh();
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
					identifier: null,
				});

				childData.parent = parent;
				childData.depth = parent?.depth + 1 ?? 0;
				updateData(childData);
				childrenData.push(childData);
			}
		}

		if (parent != null) {
			parent.children = childrenData;
		}
		return childrenData;
	}

	function updateData(data: TreeItemData) {
		data.children = null; // invalidate children if we are regenerating the tree
		data.name = StringTools.htmlEscape(getItemName(cast data.item));
		data.identifier = getIdentifier(cast data.item);
	}

	function flatten() {
		flatList.resize(0);
		function rec(items: Array<TreeItemData>) {
			for (item in items) {
				if (!item.filterState.has(Visible)) continue;
				flatList.push(item);
				if (isOpen(item)) {
					if (item.children == null) {
						generateChildren(item);
					}
					rec(item.children);
				}
			}
		}
		rec(rootData);
	}

	public function isOpen(data: TreeItemData) : Bool {
		return (openState.get(data.identifier) ?? false) || data.filterState.has(Open);
	}

	public function isSelected(data: TreeItemData) : Bool {
		return selectedElements.get(cast data) == true;
	}
}

#end