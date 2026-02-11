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
	}

	override public function update(dt: Float) {
		super.update(dt);

		tryCall(() -> ui.updateStyle(dt));

		updateProfiling();
	}

	function updateProfiling() {
		if (hxd.Key.isPressed(hxd.Key.F9)) {
			if (!hide.tools.Profiler.processing) {
				trace("Strating profiler");
				hide.tools.Profiler.start();
			} else {
				hide.tools.Profiler.save();
				var converted = Sys.command(".vscode\\post_profile.bat") == 0;
				hide.tools.Profiler.stop();
				trace("Stopping profiler", converted);
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