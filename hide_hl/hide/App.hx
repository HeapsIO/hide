package hide;

class App extends hxd.App {
	public var ui : hrt.ui.HuiBase;
	public var ide : hide.Ide;
	static public var DEBUG = false;

	override public function init() {

		ui = new hrt.ui.HuiBase(s2d);
		ide = new hide.Ide();
	}

	override public function update(dt: Float) {

		tryCall(() -> ui.updateStyle(dt));


	}

	static function main() {
		DEBUG = #if hl hl.Api.hasDebugger() #else false #end;

		hxd.Res.initLocal();

		new App();
	}

	static function tryCall(f: Void->Void) {
		if (DEBUG)
			f();
		else
			try {
				f();
			} catch(e) {

			}
	}
}