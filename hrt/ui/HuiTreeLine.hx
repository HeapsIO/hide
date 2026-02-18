package hrt.ui;
import hrt.ui.HuiTree;

#if hui

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
		title.text = data.name;
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