package hrt.ui;

import hrt.impl.TextureType;
import hrt.impl.Gradient;

#if hui

class HuiTextureChoice extends HuiElement {
	static var SRC =
		<hui-texture-choice>
			<hui-element id="widget">
				<hui-file-picker id="file-picker"/>
				<hui-gradient-box id="gradient-box"/>
			</hui-element>
			<hui-button-menu(menu) id="button-menu">
				<hui-icon("vertical_dots_small")/>
			</hui-button-menu>
		</hui-texture-choice>

	public function new(?parent) {
		super(parent);
		initComponent();

		filePicker.onValueChanged = () -> {
			value = filePicker.value;
			onValueChange(false);
		}

		gradientBox.onValueChanged = (tempChange) -> {
			(value:Dynamic).data = gradientBox.value;
			onValueChange(tempChange);
		}

		refreshType();
	}

	public var value(default, set): Any = null;

	function set_value(v) {
		value = v;
		refreshType();
		return value;
	}

	function menu() : Array<hrt.ui.HuiMenu.MenuItem> {
		return [
			{
				label: "Change to Texturepath",
				click: function() changeTextureType(TextureType.path),
				enabled: Utils.getTextureType(value) != TextureType.path
			},
			{
				label: "Change to Gradient",
				click: function() changeTextureType(TextureType.gradient),
				enabled: Utils.getTextureType(value) != TextureType.gradient
			},
		];
	}

	function refreshType() {
		var type = Utils.getTextureType(value);
		filePicker.visible = type == TextureType.path;
		gradientBox.visible = type == TextureType.gradient;

		switch(type) {
			case TextureType.path:
				filePicker.value = value;
			case TextureType.gradient:
				gradientBox.value = Utils.getGradientData(value);
			default:
		}
	}

	function changeTextureType(newType:TextureType) {
		switch (newType) {
			case TextureType.path:
				set_value(null);
			case TextureType.gradient:
				set_value({type: TextureType.gradient, data: Gradient.getDefaultGradientData()});
			default:
				throw "unhandled TextureType change";
		}

		refreshType();
		onValueChange(false);
	}

	public dynamic function onValueChange(tempChange: Bool) {};
}
#end