package hrt.ui;

#if hui
class HuiGameLauncherWidget extends HuiElement {
	static var SRC =
		<hui-game-launcher-widget>
			<hui-button id="play-btn" class="quiet">
				<hui-icon(HuiRes.ui.icons.play) id="play-icon"/>
			</hui-button>
			<hui-button id="target-btn" class="quiet" tip={"Choose the .hxml used to build and run the game"}>
				<hui-text("") id="target-text"/>
				<hui-icon(HuiRes.ui.icons.drop_down)/>
			</hui-button>
		</hui-game-launcher-widget>

	var lastState : hide.tools.GameLauncher.State = null;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		playBtn.onClick = (_) -> hide.tools.GameLauncher.toggle();
		targetBtn.onClick = (_) -> {
			uiBase.openMenu(targetMenu(), {}, {object: Element(targetBtn), directionX: StartInside, directionY: EndOutside});
		}
		refreshTarget();
	}

	function targetMenu() : Array<HuiMenu.MenuItem> {
		var targets = hide.tools.GameLauncher.listTargets();
		if (targets.length == 0)
			return [{label: "No .hxml with -main and -hl found at the project root", enabled: false}];

		var current = hide.tools.GameLauncher.getCurrentHxml();
		return [
			for (t in targets) {
				label: haxe.io.Path.withoutDirectory(t.hxml),
				tooltip: '${t.main} -> ${StringTools.replace(t.output, hide.Ide.inst.projectDir + "/", "")}',
				checked: t.hxml == current,
				click: () -> {
					hide.tools.GameLauncher.setCurrentHxml(t.hxml);
					refreshTarget();
				},
			}
		];
	}

	function refreshTarget() {
		var hxml = hide.tools.GameLauncher.getCurrentHxml();
		targetText.text = hxml != null ? haxe.io.Path.withoutDirectory(hxml) : "No game";
	}

	override function sync(ctx: h2d.RenderContext) {
		var state = hide.tools.GameLauncher.state;
		if (state != lastState) {
			lastState = state;
			dom.toggleClass("compiling", state == Compiling);
			dom.toggleClass("running", state == Running);
			targetBtn.enable = state == Idle;
			playIcon.setIcon(state == Idle ? HuiRes.ui.icons.play : HuiRes.ui.icons.close);
			playBtn.tip = switch (state) {
				case Idle: "Run game (F5)";
				case Compiling: "Cancel compilation (F5)";
				case Running: "Stop game (F5)";
			}
		}
		super.sync(ctx);
	}
}

#end
