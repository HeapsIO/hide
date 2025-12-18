package hrt.prefab.editor;

class QuickTool extends Tool {

	dynamic function customOnEnter(): Void {};
	dynamic function customOnQuit(): Void {};
	dynamic function customUpdate(dt: Float): Void{};

	public function new(ctx, onEnter, onQuit, update) {
		super(ctx);
		if (onEnter != null)
			customOnEnter = onEnter;
		if (onQuit != null)
			customOnQuit = onQuit;
		if (update != null)
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