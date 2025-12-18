package hrt.prefab.editor;

class Tool {
	public var mouseSupport(default, set): Bool = false;

	/**
		A foreground tool automatically remove the previous foreground tool when entered
	**/
	public var foreground: Bool = true;

	var enabled: Bool;
	var interactive: h2d.Interactive;

	var s3d: h3d.scene.Scene;
	var s2d: h2d.Scene;
	var ctx: EditContext2;

	var debugText: h2d.Text;

	function set_mouseSupport(v: Bool) {
		mouseSupport = v;
		syncInteractive();
		return mouseSupport;
	}

	public function new(ctx: EditContext2) {
		this.ctx = ctx;
	}

	final public function enter() {
		if (foreground) {
			if (ctx.foregroundEditorTool != null) {
				ctx.foregroundEditorTool.quit();
			}
			ctx.foregroundEditorTool = this;
		} else {
			if(ctx.otherEditorTools.contains(this)) {
				this.quit();
			}
			ctx.otherEditorTools.push(this);
		}

		enabled = true;
		syncInteractive();

		onEnter();
	}

	function onEnter() {
		debugText = new h2d.Text(hxd.res.DefaultFont.get(), ctx.s2d);
		debugText.dropShadow = {
			dx: 1,
			dy: 1,
			color: 0,
			alpha: 0.5,
		};
		debugText.text = Type.getClassName(Type.getClass(this));
	}

	final public function quit() {
		onQuit();

		enabled = false;
		syncInteractive();

		if (foreground) {
			if (ctx.foregroundEditorTool != this)
				throw "Trying to quit this tool while it was not the foreground tool of the editor";
			ctx.foregroundEditorTool = null;
		} else {
			var removed = ctx.otherEditorTools.remove(this);
			if (!removed)
				throw "Trying to quit this tool while it was not registered in the current context";
		}
	}

	function onQuit() {
		debugText.remove();
	}

	/**
		Called once per frame
	**/
	function update(dt: Float) {

	};

	function syncInteractive() {
		if (interactive != null) {
			interactive.remove();
		}
		interactive = null;
		if (!mouseSupport || !enabled)
			return;
		interactive = new h2d.Interactive(10000, 10000, ctx.s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;
		postInitInteractive();
	}

	function postInitInteractive() {

	}
}