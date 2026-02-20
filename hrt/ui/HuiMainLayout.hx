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
				<hui-button-menu(() -> [{label: "Resources", click: () -> hide.Ide.inst.openView(@:privateAccess new hide.view.FileBrowser({rootPath: hide.Ide.inst.resourceDir}), Left)}, {label: "Scene"}, {label: "Settings"}, {label: "Gym", click: () -> hide.Ide.inst.openView(@:privateAccess new HuiViewGym({}))}])>
					<hui-text("View")/>
				</hui-button-menu>

				<hui-button-menu(() -> [{label: "Toast", menu: [{label: "Info", click:() -> addToast("Debug toast", Info), stayOpen: true}, {label: "Warning", click:() -> addToast("Debug toast", Warning), stayOpen: true}, {label: "Error", click:() -> addToast("Debug toast", Error), stayOpen: true}]}])>
					<hui-text("Debug")/>
				</hui-button-menu>
			</hui-element>

			<hui-element public id="main-panel">

			</hui-element>

			<hui-element public id="main-footer">
				<hui-text("hide_hl v0.0.0")/>

				<hui-text("fps") id="fps"/>
			</hui-element>

			<hui-element id="toast-overlay">
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
	var smoothedTime = 0.0;

	override function sync(ctx) : Void {
		super.sync(ctx);

		var frameTime = hxd.Timer.elapsedTime;
		var time = haxe.Timer.stamp();
		if (frameTime > maxFrameTime || time - lastmaxFrameTimeTime > 1.0) {
			maxFrameTime = frameTime;
			lastmaxFrameTimeTime = time;
		}

		smoothedTime = hxd.Math.lerp(smoothedTime, frameTime, 0.02);



		fps.text = 'frame: ${fmt(smoothedTime)}, max: ${fmt(maxFrameTime)}';
	}

	function fmt(f: Float) : String {
		var str = '${hxd.Math.floor(f * 10000.0) / 10}';
		if (str.indexOf(".") == -1) {
			str += ".0";
		}
		return str + "ms";
	}

	function rebuild() {
		removeChildren();
		@:privateAccess dom.contentRoot = this;
		init();

		if (hide.Ide.inst.ideConfig.currentProject != null) {
			mainPanel.removeChildElements();
			projectLayout = new HuiProjectLayout(mainPanel);
		}
	}

	public function addToast(message:String, kind: HuiToast.ToastKind, ?timeout: Float) {
		for (child in toastOverlay.childElements) {
			var toast = Std.downcast(child, HuiToast);
			if (toast == null)
				continue;
			if (toast.canMerge(message, kind)) {
				toast.resetTimer();
				return;
			}
		}
		new HuiToast(message, kind, timeout, toastOverlay);
	}
}

#end