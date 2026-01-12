package hrt.ui;

#if hui
class HuiMainLayout extends HuiElement {
	static var SRC =
		<hui-main-layout>
			<hui-element public id="main-navbar">
				<hui-fmt-text("File")/>
			</hui-element>

			<hui-element id="app-panel-internal">
				<hui-element public id="left-panel" class="panel">
				</hui-element>

				<hui-splitter class="horizontal"/>

				<hui-element id="right-panel-internal">
					<hui-element public id="main-panel" class="panel">
					</hui-element>

					<hui-splitter class="vertical"/>

					<hui-element public id="bottom-panel" class="panel">
					</hui-element>
				</hui-element>
			</hui-element>

			<hui-element public id="main-footer">
				<hui-fmt-text("hide_hl v0.0.0")/>
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

#end