package hrt.ui;

#if hui
class HuiLine extends HuiElement {
	static var SRC = <hui-line>
	</hui-line>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}

	override function onAfterReflow() {
		var childrenFlow : Array<h2d.Flow> = cast children.filter((f) -> Std.isOfType(f, h2d.Flow));
		// trace(this.innerWidth);
		// for (c in childrenFlow) {
		// 	@:bypassAccessor c.minWidth = c.maxWidth = hxd.Math.floor(this.innerWidth / childrenFlow.length);
		// 	c.reflow();
		// 	// c.minWidth = c.maxWidth = hxd.Math.round(this.innerWidth / childrenFlow.length);
		// }
	}
}

#end