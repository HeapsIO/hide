package hrt.prefab.editor;

class Tool {
	public var mouseSupport(default, set): Bool = false;

	var enabled: Bool;
	var interactive: h2d.Interactive;

	var s3d: h3d.scene.Scene;
	var s2d: h2d.Scene;
	var ctx: EditContext2;

	function set_mouseSupport(v: Bool) {
		mouseSupport = v;
		syncInteractive();
		return mouseSupport;
	}

	public function new(ctx: EditContext2) {
		this.ctx = ctx;
	}

	public function enter() {
		enabled = true;
		syncInteractive();
	}

	public function quit() {
		enabled = false;
		syncInteractive();
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