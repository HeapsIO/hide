package hide;

#if !hui
#error "Need hui compiler flag"
#end

class App extends hxd.App {
	public var ui : hrt.ui.HuiBase;
	public var ide : hide.Ide;
	static public var DEBUG = false;

	override public function init() {
		super.init();

		hxd.Window.getInstance().title = "HideHL";
		ide = new hide.Ide();
		ui = new hrt.ui.HuiBase(this, s2d);
	}

	override public function update(dt: Float) {
		super.update(dt);

		tryCall(() -> ui.updateStyle(dt));
	}

	static function main() {
		DEBUG = #if hl hl.Api.hasDebugger() #else false #end;

		hxd.Res.initLocal();

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