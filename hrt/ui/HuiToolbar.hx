package hrt.ui;

#if hui
class HuiToolbar extends HuiElement {
	static var SRC = <hui-toolbar>
	</hui-toolbar>

	var widgets : Array<HuiElement>;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();
	}

	public function addWidget(widget : HuiElement) {
		this.addChild(widget);
	}
}

#end