package hrt.ui;
import hrt.ui.HuiTreeLine;

#if hui

enum RefreshFlag {
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

	/**TreeItem -> TreeItemData map**/
	var itemMap : Map<{}, TreeItemData> = [];

	/**Identifier to item open state (item if considered closed if no entry exist in the map)**/
	var openState: Map<String, Bool> = [];


	var refreshFlags : RefreshFlags = RefreshFlags.ofInt(0);

	public function new(?parent) {
		super(parent);
		initComponent();

		list.generateItem = generateItem;
		requestRefresh(RegenerateFlatten);
		requestRefresh(RootData);
	}

	function requestRefresh(refreshFlag: RefreshFlag) {
		refreshFlags.set(refreshFlag);
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

			refreshFlags = RefreshFlags.ofInt(0);
		}
	}

	function generateItem(data: TreeItemData) : HuiElement {
		var line = new HuiTreeLine(data);

		line.onClick = (e) -> {
			if (hasChildren(cast data.item)) {
				if (!isOpen(data)) {
					generateChildren(data);
					openState.set(data.identifier, true);
				} else {
					openState.remove(data.identifier);
				}
				refreshFlags.set(RegenerateFlatten);
			}
		}

		return line;
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

	function isOpen(data: TreeItemData) {
		return (openState.get(data.identifier) ?? false) || data.filterState.has(Open);
	}
}

#end