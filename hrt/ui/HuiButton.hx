package hrt.ui;

#if hui
class HuiButton extends HuiElement {
	static var SRC = <hui-button>
	</hui-button>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();
	}
}

#end