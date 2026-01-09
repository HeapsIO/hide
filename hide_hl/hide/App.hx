package hide;

class App extends hxd.App {
	public var ui : hrt.ui.HuiBase;
	public var ide : hide.Ide;

	override public function init() {

		ui = new hrt.ui.HuiBase(s2d);
		ide = new hide.Ide();
	}

	static function main() {
		hxd.Res.initLocal();

		new App();
	}
}