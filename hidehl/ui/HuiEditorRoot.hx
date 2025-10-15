package hidehl.ui;

class HuiEditorRoot extends HuiElement {
	static var SRC =
		<hui-editor-root>
			<hui-element id="panel-left" public></hui-element>
			<hui-element id="panel-middle" public>
				// <scene id="scene-main" public/>
			</hui-element>
			<hui-element id="panel-right" public>
			</hui-element>
		</hui-editor-root>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}