package hrt.ui;

#if hui

class HuiGradientBox extends HuiElement {
	static var SRC =
		<hui-gradient-box>
			<bitmap id="gradient-display"/>
		</hui-gradient-box>

	public var value(default, set): hrt.impl.Gradient.GradientData;
	var editor: hrt.ui.HuiGradientEditor;

	public function new(?parent) {
		super(parent);
		initComponent();

		value = hrt.impl.Gradient.getDefaultGradientData();

		var alphaShader = new hrt.shader.PreviewShaderAlpha();
		alphaShader.scale.set(8,4);
		gradientDisplay.addShader(alphaShader);

		refreshGradient();

		onClick = click;
	}

	public function set_value(v: hrt.impl.Gradient.GradientData) : hrt.impl.Gradient.GradientData {
		value = v;
		refreshGradient();
		if (editor != null) {
			editor.value = value;
		}
		return value;
	}

	public dynamic function onValueChanged(isTempChanged: Bool) {

	}

	override function onAfterReflow() {
		gradientDisplay.x = 2;
		gradientDisplay.y = 2;
		gradientDisplay.width = innerWidth-4;
		gradientDisplay.height = innerHeight-4;
	}

	public function refreshGradient() {
		var tex = hrt.impl.Gradient.textureFromData(value);
		gradientDisplay.tile = h2d.Tile.fromTexture(tex);
	}

	public function click(e: hxd.Event) {
		if (editor == null) {
			editor = new HuiGradientEditor();
			editor.value = value;
			editor.onCloseListeners.push(() -> {
				editor = null;
			});
			editor.onValueChanged = onEditorValueChanged;
			uiBase.addPopup(editor, { object: Element(this), directionX: StartInside, directionY: EndOutside });
		} else {
			editor.close();
			editor = null;
		}
	}

	function onEditorValueChanged(tempChange: Bool) {
		refreshGradient();
		onValueChanged(tempChange);
	}
}

#end