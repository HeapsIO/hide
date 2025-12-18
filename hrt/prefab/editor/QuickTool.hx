package hrt.prefab.editor;

class QuickTool extends Tool {

	dynamic function customOnEnter(): Void {};
	dynamic function customOnQuit(): Void {};
	dynamic function customUpdate(dt: Float): Void{};

	public function new(ctx, onEnter, onQuit, update) {
		super(ctx);
		customOnEnter = onEnter;
		customOnQuit = onQuit;
		customUpdate = update;
	}

	override function onEnter() {
		customOnEnter();
	}

	override function onQuit() {
		customOnQuit();
	}

	override function update(dt:Float) {
		customUpdate(dt);
	}
}