package hrt.ui;

#if hui

class HuiColorBox extends HuiElement {
	static var SRC = <hui-color-box>
	</hui-color-box>

	public var value(default, set) : Int = 0xFF00FF;
	public var useAlpha: Bool = false;
	var pickerGuard : Int = 0;
	var picker : HuiColorPicker = null;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		function onPickerClose() {
			picker.remove();
			picker = null;
		}

		this.backgroundType = "hui";
		this.huiBg.imageTile = h2d.Tile.fromColor(value, 60, 20);
		this.onClick = (e : hxd.Event) -> {
			if (picker == null) {
				picker = new HuiColorPicker(this, null);
				uiBase.addPopup(picker, { object: Element(this), directionX: StartInside, directionY: EndOutside });
				picker.setColor(value, useAlpha);
				picker.onCloseListeners.push(onPickerClose);
				picker.onValueChanged = (isTemporary) -> {
					pickerGuard++;
					value = picker.getColor(useAlpha);
					pickerGuard--;
					onValueChanged(isTemporary);
				};
			}
			else {
				picker.close();
			}
		};
	}

	public function set_value(v : Int) {
		this.huiBg.imageTile = h2d.Tile.fromColor(v, 60, 20);
		return value = v;
	}



	public dynamic function onValueChanged(isTemporary: Bool) {}
}

#end