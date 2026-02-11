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

				<hui-text("fps") id="fps"/>
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

	var maxFrameTime = 0.0;
	var lastmaxFrameTimeTime = 0.0;

	override function sync(ctx) : Void {
		super.sync(ctx);

		var frameTime = hxd.Timer.elapsedTime;
		var time = haxe.Timer.stamp();
		if (frameTime > maxFrameTime || time - lastmaxFrameTimeTime > 1.0) {
			maxFrameTime = frameTime;
			lastmaxFrameTimeTime = time;
		}

		function fmt(f: Float) : String {
			var str = '${hxd.Math.floor(f * 10000.0) / 10}';
			if (str.indexOf(".") == -1) {
				str += ".0";
			}
			return str + "ms";
		}

		fps.text = 'frame: ${fmt(frameTime)}, max: ${fmt(maxFrameTime)}';
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