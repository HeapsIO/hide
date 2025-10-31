package hrt.ui;

class HuiElement extends h2d.Flow implements h2d.domkit.Object {
	static var SRC =
		<hui-element>
		</hui-element>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}