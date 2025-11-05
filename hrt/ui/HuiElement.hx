package hrt.ui;

#if domkit

class HuiElement extends h2d.Flow #if domkit implements h2d.domkit.Object #end {
	static var SRC =
		<hui-element>
		</hui-element>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}

#end
