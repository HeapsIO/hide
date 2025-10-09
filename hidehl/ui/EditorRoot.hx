package hidehl.ui;

class EditorRoot extends Element {
	static var SRC =
		<editor-root>
			<element id="panel-left" public></element>
			<element id="panel-middle" public>
				// <scene id="scene-main" public/>
			</element>
			<element id="panel-right" public>
			</element>
		</editor-root>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}