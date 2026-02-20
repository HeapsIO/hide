package hrt.ui;

typedef HuiSelectOption = {
	label: String,
	value: Dynamic
}

#if hui
class HuiSelect extends HuiElement {
	static var SRC = <hui-select>
		<hui-element id="value-text-container"><hui-text id="value-text"/></hui-element>
		<hui-icon("dropDown")/>
	</hui-select>

	public var value(default, set) : Dynamic;
	public var items : Array<HuiSelectOption> = [];

	public function new(?parent) {
		super(parent);
		initComponent();

		this.onClick = (e: hxd.Event) -> {
			uiBase.openMenu([for (i in items) { label: i.label, click:() -> { value = i.value; onValueChanged();} }], {}, { object: Element(this), directionX: Stretch, directionY: EndOutside });
		}
	}

	public function set_value(v: Dynamic) {
		for (i in items) {
			if (i.value == v) {
				valueText.text = i.label;
				value = i.value;
				break;
			}
		}

		return value;
	}

	public dynamic function onValueChanged() {}
}

#end