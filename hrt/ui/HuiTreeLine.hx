package hrt.ui;
import hrt.ui.HuiTree;

#if hui

class HuiTreeLine extends HuiElement {
	static var SRC =
		<hui-tree-line>
			<hui-element id="caret"/>
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
		refresh();
	}

	public function refresh() {
		title.text = data.name;
		paddingLeft = data.depth * 5;
		dom.toggleClass("children", (cast tree:HuiTree<Dynamic>).hasChildren(data.item));
		dom.toggleClass("open", (cast tree:HuiTree<Dynamic>).isOpen(data));
	}
}

#end