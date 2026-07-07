package hrt.ui;

#if hui
/**
	Like HuiVirtual list, but displays items on a grid width fixed width and height instead of a list
**/
@:access(hrt.ui.HuiVirtualList)
class HuiVirtualGrid<T> extends HuiElement {
	var items: Array<T> = [];
	var virtualList: HuiVirtualList<Int>;
	var itemsPerRow: Int = 4;
	var needRefresh(default, set): Bool = false;

	function set_needRefresh(v: Bool) {
		virtualList.needRefresh = v;
		return needRefresh = v;
	}

	/**
		Items in the grid must have a fixed width and height
	**/
	@:p public var itemBaseWidth(default, set): Float = 64;
	@:p public var itemBaseHeight(default, set): Float = 64;

	function set_itemBaseWidth(v: Float) {needRefresh = true; updateItemsPerRow(); return itemBaseWidth = v;}
	function set_itemBaseHeight(v: Float) {needRefresh = true; return itemBaseHeight = v;}

	public var generateItem(default, set) : (item: T) -> HuiElement = null;

	function set_generateItem(v) {needRefresh = true; return generateItem = v;}

	public function new(?parent) {
		super(parent);
		initComponent();

		virtualList = new HuiVirtualList(this);
		virtualList.setItems([]);

		virtualList.generateItem = listGenerateItem;
		onAfterReflow = afterReflow;
	}

	public function setItems(items: Array<T>) : Void {
		this.items = items;
		needRefresh = true;
		updateVirtualListItems();
	}

	function listGenerateItem(itemId: Int) {
		var row = new HuiVirtualGridRow();
		row.setHeight(Std.int(itemBaseHeight));
		for (i in itemId...itemId+itemsPerRow) {
			var item = items[i];
			if (item == null)
				break;
			var element = generateItem(item);
			var cell = new HuiVirtualGridCell(row);
			cell.setWidth(Std.int(itemBaseWidth));
			cell.setHeight(Std.int(itemBaseHeight));
			cell.addChild(element);
		}
		return row;
	}

	function afterReflow() {
		updateItemsPerRow();
	}

	function updateItemsPerRow() {
		itemsPerRow = hxd.Math.floor(innerWidth / itemBaseWidth);
		updateVirtualListItems();
	}

	function updateVirtualListItems() {
		virtualList.items.resize(0);
		for (i in 0...hxd.Math.ceil(items.length/itemsPerRow)) {
			virtualList.items.push(i * itemsPerRow);
		}
		virtualList.setItems(virtualList.items);
	}
}

class HuiVirtualGridRow extends HuiElement {
	static var SRC =
		<hui-virtual-grid-row>
		</hui-virtual-grid-row>

	public function new(?parent) {
		super(parent);
		initComponent();
	}
}

class HuiVirtualGridCell extends HuiElement {

}
#end