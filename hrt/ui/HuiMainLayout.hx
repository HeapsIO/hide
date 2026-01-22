package hrt.ui;

#if hui

@:uiInitFunction(init)
class HuiMainLayout extends HuiElement {
	static var SRC =
		<hui-main-layout>
			<hui-element public id="main-navbar">
				<hui-button-menu(() -> [{label: "Open Project ..."}, {label: "Recent", menu: [{label: "Wartales"}, {label: "Mog"}, {label: "Northgard 2"}, {label: "Spacecraft"}, {label: "D4X2"}]}])>
					<hui-text("File")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "Copy"}, {label: "Paste"}, {label: "Cut"}, {isSeparator: true}, {label: "Other stuff", menu: [{label: "Hello there"}]}])>
					<hui-text("Edit")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "CDB"}, {label: "Scene"}, {label: "Settings"}, {label: "Gym"}])>
					<hui-text("View")/>
				</hui-button-menu>
			</hui-element>

			<hui-split-container id="app-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal} save-display-key="left-panel-split">
				<hui-element public id="left-panel" class="panel">
				</hui-element>


				<hui-split-container id="right-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Vertical} anchor-to={hrt.ui.HuiSplitContainer.AnchorTo.End} save-display-key="bottom-panel-split">
					<hui-tab-view-container public id="main-panel">
						<hui-element>
							<hui-text("1")/>
						</hui-element>
						<hui-element>
							<hui-text("2")/>
						</hui-element>
						<hui-element>
							<hui-text("3")/>
						</hui-element>
					</hui-tab-view-container>

					<hui-element public id="bottom-panel" class="panel">
					</hui-element>
				</hui-split-container>
			</hui-split-container>

			<hui-element public id="main-footer">
				<hui-text("hide_hl v0.0.0")/>
			</hui-element>
		</hui-main-layout>

	public function new(?parent: h2d.Object) {
		super(parent);
		init();
	}

	function init() {
		initComponent();
	}

	function rebuild() {
		removeChildren();
		@:privateAccess dom.contentRoot = this;
		init();
	}
}

#end