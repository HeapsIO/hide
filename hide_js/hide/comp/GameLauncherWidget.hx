package hide.comp;

import hide.tools.GameLauncher;

class GameLauncherWidget extends Component {
	static var shortcutRegistered = false;

	var playBtn : Element;
	var playIcon : Element;
	var targetBtn : Element;
	var targetText : Element;

	public function new(?parent: Element) {
		super(parent, new Element('
			<div class="game-launcher">
				<div class="play-btn"><div class="icon ico"></div></div>
				<div class="target-btn" title="Choose the .hxml used to build and run the game">
					<span></span>
					<div class="icon ico ico-caret-down"></div>
				</div>
			</div>'));

		playBtn = element.find(".play-btn");
		playIcon = playBtn.find(".icon");
		targetBtn = element.find(".target-btn");
		targetText = targetBtn.find("span");

		playBtn.click((_) -> GameLauncher.toggle());
		targetBtn.click((_) -> {
			if (GameLauncher.state == Idle)
				ContextMenu.createDropdown(targetBtn.get(0), targetMenu(), {search: None});
		});

		if (!shortcutRegistered) {
			shortcutRegistered = true;
			js.Browser.document.body.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
				if (hide.ui.Keys.matchJsEvent("gameLauncher.toggle", e, hide.Ide.inst.currentConfig)) {
					GameLauncher.toggle();
					e.preventDefault();
					e.stopPropagation();
				}
			}, true);
		}

		GameLauncher.onStateChange = refreshState;
		refreshState();
		refreshTarget();
	}

	function targetMenu() : Array<hrt.ui.HuiMenu.MenuItem> {
		var targets = GameLauncher.listTargets();
		if (targets.length == 0)
			return [{label: "No .hxml with -main and -hl found at the project root", enabled: false}];

		var current = GameLauncher.getCurrentHxml();
		var project = GameLauncher.getProjectHxml();
		return [
			for (t in targets) {
				label: haxe.io.Path.withoutDirectory(t.hxml) + (t.hxml == project ? " (project default)" : ""),
				tooltip: '${t.main} -> ${StringTools.replace(t.output, ide.projectDir + "/", "")}',
				checked: t.hxml == current,
				click: () -> {
					GameLauncher.setCurrentHxml(t.hxml);
					refreshTarget();
				},
			}
		];
	}

	function refreshTarget() {
		var hxml = GameLauncher.getCurrentHxml();
		targetText.text(hxml != null ? haxe.io.Path.withoutDirectory(hxml) : "No game");
	}

	function refreshState() {
		var state = GameLauncher.state;
		var key = ide.currentConfig.get("key.gameLauncher.toggle");
		element.toggleClass("compiling", state == Compiling);
		element.toggleClass("running", state == Running);
		targetBtn.toggleClass("disabled", state != Idle);
		playIcon.toggleClass("ico-play", state == Idle);
		playIcon.toggleClass("ico-stop", state != Idle);
		playBtn.attr("title", switch (state) {
			case Idle: 'Run game ($key)';
			case Compiling: 'Cancel compilation ($key)';
			case Running: 'Stop game ($key)';
		});
	}
}
