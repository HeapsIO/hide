package hidehl.ui;

class Element extends h2d.Flow implements h2d.domkit.Object {
	static var SRC =
		<element>
		</element>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}