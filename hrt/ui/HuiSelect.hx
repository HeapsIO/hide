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

		this.onWheel = (e : hxd.Event) -> {
			var valueIdx = 0;
			for (idx => i in items) {
				if (i.value == this.value) {
					valueIdx = idx;
					break;
				}
			}

			valueIdx = Std.int(hxd.Math.clamp(valueIdx + (e.wheelDelta > 0 ? 1 : -1), 0, items.length - 1));
			if (value != items[valueIdx]) {
				this.set_value(items[valueIdx].value);
				onValueChanged();
			}
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