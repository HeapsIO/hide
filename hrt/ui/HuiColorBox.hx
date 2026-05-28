package hrt.ui;

#if hui

class HuiColorBox extends HuiElement {
	static var SRC = <hui-color-box>
		<bitmap id="bitmap"/>
	</hui-color-box>

	public var value(default, set) : Int = 0xFF00FF;
	public var useAlpha: Bool = false;
	var pickerGuard : Int = 0;
	var picker : HuiColorPicker = null;
	var alphaShader : hrt.shader.PreviewShaderAlpha;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		function onPickerClose() {
			picker.remove();
			picker = null;
		}

		alphaShader = new hrt.shader.PreviewShaderAlpha();
		alphaShader.split = 0.5;

		this.backgroundType = "hui";
		bitmap.tile = h2d.Tile.fromColor(0xFFFFFF);
		bitmap.addShader(alphaShader);
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

		set_value(value);
	}

	override function onAfterReflow() {
		bitmap.x = 1;
		bitmap.y = 1;
		bitmap.width = calculatedWidth-2;
		bitmap.height = calculatedHeight-2;
	}

	public function set_value(v : Int) {
		bitmap.color = h3d.Vector4.fromColor(v);
		return value = v;
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}

#end