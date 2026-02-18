package hrt.ui;

#if hui
class HuiCheckbox extends HuiElement {
	static var SRC = <hui-checkbox>
		<hui-element id="icon"/>
	</hui-checkbox>

	@:p public var value : Bool = false;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		icon.visible = value;
		icon.propagateEvents = true;
		onClick = (e: hxd.Event) -> {
			value = !value;
			icon.visible = value;
		}
	}
}
#end
