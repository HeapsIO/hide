package hrt.ui;
import hrt.ui.HuiTree;

#if hui

@:access(hrt.ui.HuiTree)
class HuiTreeLine extends HuiElement {
	static var SRC =
		<hui-tree-line>
			<hui-element id="caret"/>
			<hui-element id="icon"/>
			<hui-text("") id="title"/>
		</hui-tree-line>

	var data : TreeItemData;
	var tree : Any;

	public function new(data: TreeItemData, tree: Any, ?parent) {
		super(parent);
		initComponent();
		this.data = data;
		makeInteractive();
		this.tree = tree;

		caret.onPush = (e) -> {
			if (e.button == 0)
				onCaretClick();
		}

		onPush = (e) -> {
			if (e.button == 0) {
				onItemSelect(hxd.Key.isDown(hxd.Key.SHIFT), hxd.Key.isDown(hxd.Key.CTRL));
			}
		}
	}

	public function refresh() {
		var tree : HuiTree<Dynamic> = tree;
		if (tree.searchBarContainer.visible && data.searchRanges != null) {
			title.text = hide.Search.splitSearchRanges(data.name, data.searchRanges, "<h>", "</h>");
		} else {
			title.text = data.name;
		}
		icon.backgroundType = "hui";
		icon.huiBg.image = { path: data.icon, mode: Fit };
		paddingLeft = data.depth * 5;
		dom.toggleClass("children", tree.hasChildren(data.item));
		dom.toggleClass("open", tree.isOpen(data));
		dom.toggleClass("selected", tree.isSelected(data));
		@:privateAccess dom.toggleClass("keyboard-selected", tree.keyboardFocus == data);
	}

	dynamic public function onCaretClick() {

	}

	dynamic public function onItemSelect(shift: Bool, ctrl: Bool) {

	}
}

#end