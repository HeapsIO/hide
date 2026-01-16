package hrt.ui;

#if hui
class HuiMainLayout extends HuiElement {
	static var SRC =
		<hui-main-layout>
			<hui-element public id="main-navbar">
				<hui-button-menu(() -> [{label: "Open Project ..."}, {label: "Recent", menu: [{label: "Wartales"}, {label: "Mog"}, {label: "Northgard 2"}, {label: "Spacecraft"}, {label: "D4X2"}]}])>
					<hui-fmt-text("File")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "Copy"}, {label: "Paste"}, {label: "Cut"}, {isSeparator: true}, {label: "Other stuff", menu: [{label: "Hello there"}]}])>
					<hui-fmt-text("Edit")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "CDB"}, {label: "Scene"}, {label: "Settings"}, {label: "Gym"}])>
					<hui-fmt-text("View")/>
				</hui-button-menu>
			</hui-element>

			<hui-split-container id="app-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal}>
				<hui-element public id="left-panel" class="panel">
				</hui-element>


				<hui-split-container id="right-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Vertical}>
					<hui-element public id="main-panel" class="panel">
					</hui-element>

					<hui-element public id="bottom-panel" class="panel">
					</hui-element>
				</hui-split-container>
			</hui-split-container>

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