package hrt.ui;

#if hui

@:uiInitFunction(init)
class HuiMainLayout extends HuiElement {
	static var SRC =
		<hui-main-layout>
			<hui-element public id="main-navbar">
				<hui-button-menu(fileMenu)>
					<hui-text("File")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "Copy"}, {label: "Paste"}, {label: "Cut"}, {isSeparator: true}, {label: "Other stuff", menu: [{label: "Hello there"}]}])>
					<hui-text("Edit")/>
				</hui-button-menu>
				<hui-button-menu(() -> [{label: "CDB"}, {label: "Scene"}, {label: "Settings"}, {label: "Gym"}])>
					<hui-text("View")/>
				</hui-button-menu>
			</hui-element>

			<hui-element public id="main-panel">

			</hui-element>

			<hui-element public id="main-footer">
				<hui-text("hide_hl v0.0.0")/>
			</hui-element>
		</hui-main-layout>

	public var projectLayout : HuiProjectLayout;

	public function new(?parent: h2d.Object) {
		super(parent);
		init();
	}

	function init() {
		initComponent();
	}

	function fileMenu() : Array<HuiMenu.MenuItem> {
		return [
			{label: "Open Project ...", click: () -> hide.Ide.inst.chooseProject()},
			{label: "Recent", menu: recentMenu(), enabled: hide.Ide.inst.ideConfig.recentProjects.length > 0}
		];
	}

	function recentMenu() : Array<HuiMenu.MenuItem> {
		return [
			for (project in hide.Ide.inst.ideConfig.recentProjects) {
				label: project,
				click: @:privateAccess hide.Ide.inst.setProject.bind(project),
			}
		];
	}

	function rebuild() {
		removeChildren();
		@:privateAccess dom.contentRoot = this;
		init();
	}

	public function onSetProject() {
		mainPanel.removeChildElements();
		projectLayout = new HuiProjectLayout(mainPanel);
	}
}

#end