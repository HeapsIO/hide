package hrt.ui;

#if domkit

class HuiSplitter extends HuiElement {
	static var SRC =
		<hui-splitter>
		</hui-splitter>

	@:prop

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		var parentFlow = Std.downcast(parent, h2d.Flow);
		if (parentFlow == null)
			throw "Splitter parent must be a flow";


	}
}

#end