package hrt.ui;

class HuiMainLayout extends HuiElement {
	static var SRC =
		<hui-main-layout>
			<hui-element public id="navbar">
				<hui-fmt-text("File")/>
			</hui-element>

			<hui-element id="app-panel-internal">
				<hui-element public id="left-panel">
				</hui-element>

				<hui-splitter/>

				<hui-element id="right-panel-internal">
					<hui-element public id="main-panel">
					</hui-element>

					<hui-splitter/>

					<hui-element public id="bottom-panel">
					</hui-element>
				</hui-element>
			</hui-element>

		</hui-main-layout>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		var parentFlow = Std.downcast(parent, h2d.Flow);
		if (parentFlow == null)
			throw "Splitter parent must be a flow";
	}
}