package hrt.ui;

typedef HuiSelectOption = {
	label: String,
	value: Dynamic
}

#if hui
class HuiSelect extends HuiElement {
	static var SRC = <hui-select>
		<hui-element id="value-text-container"><hui-text id="value-text"/></hui-element>
		<hui-icon(HuiRes.ui.icons.drop_down)/>
	</hui-select>

	public var value(default, set) : Dynamic;
	public var items : Array<HuiSelectOption> = [];
	var menu : HuiMenu = null;

	public function new(?parent) {
		super(parent);
		initComponent();

		this.onPush = (e: hxd.Event) -> {
			if (e.button == 0) {
				if (menu != null) {
					menu.close();
				}
				else {
					menu = uiBase.openMenu([for (i in items) { label: i.label, click:() -> { value = i.value; onValueChanged();} }], {}, { object: Element(this), directionX: Stretch, directionY: EndOutside });
					menu.onCloseListeners.push(() -> menu = null);
				}
			}
		}
	}

	public function set_value(v: Dynamic) {
		var found = false;
		if (v == null) {
			value = null;
			valueText.text = "-- None --";
		} else {
			for (i in items) {
				if (i.value == v) {
					valueText.text = i.label;
					value = i.value;
					found = true;
					break;
				}
			}
			if (!found) {
				value = v;
				valueText.text = '$value (missing)';
			}
		}

		return value;
	}

	public dynamic function onValueChanged() {}
}

#end