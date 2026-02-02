package hrt.ui;
import hrt.ui.HuiTree;

#if hui

class HuiTreeLine extends HuiElement {
	static var SRC =
		<hui-tree-line>
			<hui-text("") id="title"/>
		</hui-tree-line>

	var data : TreeItemData;

	public function new(data: TreeItemData, ?parent) {
		super(parent);
		initComponent();
		this.data = data;
		makeInteractive();
		//this.tree = tree;
		refresh();
	}

	function refresh() {
		title.text = data.name;
		paddingLeft = data.depth * 10;
	}
}

#end