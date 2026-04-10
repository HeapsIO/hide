package hrt.ui;

#if hui
class HuiToggle extends HuiElement {
	static var SRC = <hui-toggle>
	</hui-toggle>

	public var toggled(default, set) : Bool = false;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();
	}

	function set_toggled(b : Bool) {
		this.dom.toggleClass("toggled", b);
		return this.toggled = b;
	}
}

#end