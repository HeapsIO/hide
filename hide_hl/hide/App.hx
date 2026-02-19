package hide;

#if !hui
#error "Need hui compiler flag"
#end

class App extends hxd.App {
	public var ui : hrt.ui.HuiBase;
	public var ide : hide.Ide;
	static public var DEBUG = false;
	static public var fs : hxd.fs.EmbedFileSystem;

	override public function init() {
		super.init();

		hxd.Window.getInstance().title = "HideHL";
		ide = new hide.Ide();
		ide.app = this;
		ui = new hrt.ui.HuiBase(this, s2d);

		if (hide.Ide.inst.ideConfig.recentProjects?.length > 0) {
			@:privateAccess hide.Ide.inst.setProject(hide.Ide.inst.ideConfig.recentProjects[0]);
		}



		var winSize = ide.getLocalStorage("windowSize") ?? {w: 800, h: 600};
		// hxd.Window.getInstance().resize(winSize.w, winSize.h);
		#if hldx
		@:privateAccess hxd.Window.getInstance().window.maximize();
		#end
	}

	override function onResize() {
		super.onResize();
		var win = hxd.Window.getInstance();
		hide.Ide.inst.saveLocalStorage("windowSize", {w: win.width, h: win.height});
	}

	override function dispose() {
		ide.dispose();
	}

	override public function update(dt: Float) {
		super.update(dt);

		ide.update(dt);
		tryCall(() -> ui.updateStyle(dt));

		updateProfiling();
	}

	function updateProfiling() {
		if (hxd.Key.isPressed(hxd.Key.F9)) {
			if (!hide.tools.Profiler.processing) {
				Ide.showInfo("Starting profiler");
				hide.tools.Profiler.start();
			} else {
				hide.tools.Profiler.save();
				var converted = Sys.command(".vscode\\post_profile.bat") == 0;
				hide.tools.Profiler.stop();
				Ide.showInfo("Stopping profiler");
			}
		}
	}


	var bench: h3d.impl.Benchmark;

	function updateBenchmark() {
		if (hxd.Key.isPressed(hxd.Key.F6)) {
			if (bench == null) {
				bench = new h3d.impl.Benchmark();
				s2d.add(bench, 10);
				bench.enable = true;
			}
			else {
				if(!bench.measureCpu) {
					bench.measureCpu = true;
				} else {
					bench.clear();
					bench.remove();
					bench = null;
				}
			}
		}

		if ( bench != null ) {
			bench.setPosition(0, s2d.height - bench.height);
			if (bench.measureCpuThread == null)
				bench.begin();
			else
				bench.syncVisual();
		}
	}

	static function main() {
		DEBUG = #if hl hl.Api.hasDebugger() #else false #end;

		hxd.Res.initLocal();
		hrt.ui.HuiRes.init();

		new App();
	}

	static public function tryCall(f: Void->Void) {
		if (DEBUG)
			f();
		else
			try {
				f();
			} catch(e) {

			}
	}

	static public function defer(f: Void->Void) {
		haxe.Timer.delay(tryCall.bind(f), 0);
	}
}