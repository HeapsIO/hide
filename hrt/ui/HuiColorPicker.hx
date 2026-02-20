package hrt.ui;

class PreviewShaderAlpha extends hxsl.Shader {
	static var SRC = {
		var absolutePosition : Vec4;

		var pixelColor : Vec4;

		function fragment() {
			var cb = floor(mod(absolutePosition.xy / 16.0, vec2(2.0)));
			var check = mod(cb.x + cb.y, 2.0);
			var color = check >= 1.0 ? vec3(0.22) : vec3(0.44);
			pixelColor.rgb = mix(color, pixelColor.rgb, pixelColor.a);
			pixelColor.a = 1.0;
		}
	}
}

#if hui
class HuiColorBox extends HuiElement {
	static var SRC = <hui-color-box>
	</hui-color-box>

	public var value(default, set) : Int = 0xFF00FF;
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
				picker.setColor(value, false);
				picker.onCloseListeners.push(onPickerClose);
				picker.onValueChanged = (isTemporary) -> {
					pickerGuard++;
					value = picker.getColor(false);
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

class HuiColorPicker extends HuiPopup {
	static var SRC =
	 	<hui-color-picker>
			<hui-element class="picker-row">
				<hui-color-slider orientation="both" id="slider-main"/>
				<hui-color-slider orientation="vertical" id="slider-hue"/>
			</hui-element>
			<hui-select id="color-space-picker"/>
			<hui-element class="picker-col">
				<hui-element class="picker-row">
					<hui-text class="label" id="label-sec-0"/>
					<hui-color-slider id="slider-sec-0"/>
					<hui-input-box id="string-sec-0"/>
				</hui-element>
				<hui-element class="picker-row">
					<hui-text class="label" id="label-sec-1"/>
					<hui-color-slider id="slider-sec-1"/>
					<hui-input-box id="string-sec-1"/>
				</hui-element>
				<hui-element class="picker-row">
					<hui-text class="label" id="label-sec-2"/>
					<hui-color-slider id="slider-sec-2"/>
					<hui-input-box id="string-sec-2"/>
				</hui-element>

				<hui-element class="picker-row">
					<hui-text("A") class="label" id="label-alpha"/>
					<hui-color-slider id="slider-alpha"/>
					<hui-input-box id="string-alpha"/>
				</hui-element>
			</hui-element>
			<hui-element class="picker-row info">
				<hui-element>
					<hui-element id="preview">
					</hui-element>
					<hui-element id="preview-alpha">
					</hui-element>
				</hui-element>
				<hui-input-box id="color-hex"/>
			</hui-element>
		</hui-color-picker>

	static final colorModes : Array<hrt.impl.ColorSpace.ColorMode> = [
		hrt.impl.ColorSpace.colorModes[0],
		hrt.impl.ColorSpace.colorModes[2],
	];

	static var tempColor = new hrt.impl.ColorSpace.Color();
	static var tempColorVec = new h3d.Vector4();

	var color : hrt.impl.ColorSpace.Color = new hrt.impl.ColorSpace.Color();
	var box : HuiColorBox;

	var colorPickerMode = 0; // save to pref

	public function new (b : HuiColorBox, ?parent){
		box = b;
		super(parent);

		function colorSpacePickerOptions() {
			return  [ for (i => mode in colorModes) {label: mode.name, value: i}];
		}
		// EditorPrefs.inst.colorPickerMode = hxd.Math.iclamp(EditorPrefs.inst.colorPickerMode, 0, colorModes.length-1);

		initComponent();

		colorSpacePicker.items = colorSpacePickerOptions();
		colorSpacePicker.value = colorPickerMode;

		preview.backgroundType = "hui";
		previewAlpha.backgroundType = "hui";

		previewAlpha.huiBg.addShader(new PreviewShaderAlpha());
		sliderAlpha.huiBg.addShader(new PreviewShaderAlpha());

		setColorsFunctions();
		syncColorMain(color);
		syncColorSecondary(color);
		syncColorPreview(color);

		colorSpacePicker.onValueChanged = () -> {
			colorPickerMode = cast colorSpacePicker.value;
			setColorsFunctions();
			syncColorSecondary(color);
		}
	}

	override function sync(ctx:h2d.RenderContext) {
		var currentParent = box.parent;
		while(currentParent != null) {
			if (Std.downcast(currentParent, h2d.Scene) != null) {
				break;
			}
			currentParent = currentParent.parent;
		}
		if (currentParent == null) {
			this.close();
			return;
		}

		var pos = box.getAbsPos();
		x = pos.x - calculatedWidth + box.calculatedWidth;
		y = pos.y + box.calculatedHeight;
		super.sync(ctx);
	}

	function setColorsFunctions() {
		function col(x:Float,y:Float) {
			tempColorVec.set(sliderHue.value, x, (1 - y), sliderAlpha.value);
			hrt.impl.ColorSpace.HSVtoiRGB(tempColorVec, tempColor);
		}

		// main
		sliderMain.getColor = (x,y, outColor) -> {
			col(x,y);
			outColor.x = tempColor.r / 255.0;
			outColor.y = tempColor.g / 255.0;
			outColor.z = tempColor.b / 255.0;
			outColor.w = 1.0;
		}
		sliderMain.refreshTexture();

		sliderMain.onChange = (isTemporary) -> {
			col(sliderMain.value,sliderMain.value2);
			color.r = tempColor.r;
			color.g = tempColor.g;
			color.b = tempColor.b;
			syncColorSecondary(color);
			syncColorPreview(color);

			onValueChanged(isTemporary);
		}

		// hue
		sliderHue.getColor = (value,value2, outColor) -> {
			tempColorVec.set(value, 1, 1, 1.0);
			hrt.impl.ColorSpace.HSVtoiRGB(tempColorVec, tempColor);

			outColor.x = tempColor.r / 255.0;
			outColor.y = tempColor.g / 255.0;
			outColor.z = tempColor.b / 255.0;
			outColor.w = 1.0;
		}
		sliderHue.refreshTexture();

		sliderHue.onChange = (isTemporary) -> {
			tempColorVec.set(sliderHue.value, sliderMain.value, (1 - sliderMain.value2), 1.0);
			hrt.impl.ColorSpace.HSVtoiRGB(tempColorVec, tempColor);

			color.r = tempColor.r;
			color.g = tempColor.g;
			color.b = tempColor.b;
			syncColorMain();
			syncColorSecondary(color);
			syncColorPreview(color);

			onValueChanged(isTemporary);
		}

		function bindSlider(slider: HuiColorSlider, inputBox: HuiInputBox, setColorVec: (x: Float, vec: h3d.Vector4) -> Void, alpha: Bool = false) {
			slider.getColor = (value: Float, value2: Float, outColor: h3d.Vector4) -> {
				setColorVec(value, tempColorVec);
				colorModes[colorPickerMode].valueToARGB(tempColorVec, tempColor);

				outColor.x = tempColor.r / 255.0;
				outColor.y = tempColor.g / 255.0;
				outColor.z = tempColor.b / 255.0;
				if (alpha) {
					outColor.w = tempColor.a / 255.0;
				}
			}

			slider.onChange = (isTemporary) -> {
				setColorVec(slider.value, tempColorVec);
				colorModes[colorPickerMode].valueToARGB(tempColorVec, color);

				syncColorMain(color);
				syncColorSecondary();
				syncColorPreview(color);

				onValueChanged(isTemporary);
			}

			inputBox.onChange = () -> {
				var value = Std.parseInt(inputBox.textInput.text);
				if (value != null) {
					setColorVec(hxd.Math.clamp(value / 255.0), tempColorVec);
					colorModes[colorPickerMode].valueToARGB(tempColorVec, color);

					syncColorMain(color);
					syncColorSecondary(color);
					syncColorPreview(color);

					onValueChanged(true);
				}
			}

			inputBox.textInput.onFocusLost = (e) -> {
				syncColorSecondary(color, true);
				onValueChanged(false);
			}
		}

		labelSec0.text = colorModes[colorPickerMode].name.charAt(0);
		labelSec1.text = colorModes[colorPickerMode].name.charAt(1);
		labelSec2.text = colorModes[colorPickerMode].name.charAt(2);

		bindSlider(sliderSec0, stringSec0, (value, vec) -> vec.set(value, sliderSec1.value, sliderSec2.value, sliderAlpha.value));
		bindSlider(sliderSec1, stringSec1, (value, vec) -> vec.set(sliderSec0.value, value, sliderSec2.value, sliderAlpha.value));
		bindSlider(sliderSec2, stringSec2, (value, vec) -> vec.set(sliderSec0.value, sliderSec1.value, value, sliderAlpha.value));
		bindSlider(sliderAlpha, stringAlpha, (value, vec) -> vec.set(sliderSec0.value, sliderSec1.value, sliderSec2.value, value), true);

		colorHex.onChange = () -> {
			var parsedColor = hrt.impl.ColorSpace.Color.intFromString(colorHex.textInput.text, true);
			if (parsedColor == null) {
				return;
			}
			color.load(parsedColor, true);

			syncColorMain(color);
			syncColorSecondary();
			syncColorPreview(color);

			onValueChanged(true);
		}

		colorHex.textInput.onFocusLost = (e) -> {
			syncColorSecondary(color, true);
			onValueChanged(false);
		}
	}

	override function onRemove() {
		super.onRemove();
		@:privateAccess box.picker = null;
	}

	public function getColor(withAlpha: Bool) : Int {
		return color.toInt(withAlpha);
	}

	public function setColor(colorInt: Int, withAlpha: Bool) : Void {
		color.load(colorInt, withAlpha);

		syncColorMain(color);
		syncColorSecondary(color);
		syncColorPreview(color);
	}

	function syncColorMain(?newColor: hrt.impl.ColorSpace.Color) {
		if (newColor != null) {
			hrt.impl.ColorSpace.iRGBtoHSV(newColor, tempColorVec);
			sliderHue.value = tempColorVec.x;
			sliderMain.value = tempColorVec.y;
			sliderMain.value2 = (1 - tempColorVec.z);
		}
		sliderMain.refreshTexture();
		sliderHue.refreshTexture();
	}

	function syncColorSecondary(?newColor: hrt.impl.ColorSpace.Color, forceText: Bool = false) {
		if (newColor != null) {
			colorModes[colorPickerMode].ARGBToValue(newColor, tempColorVec);
			sliderSec0.value = tempColorVec.x;
			sliderSec1.value = tempColorVec.y;
			sliderSec2.value = tempColorVec.z;
			sliderAlpha.value = tempColorVec.a;
		}

		if (!stringSec0.textInput.hasFocus() || forceText) stringSec0.textInput.text = '${Math.round(sliderSec0.value * 255)}';
		if (!stringSec1.textInput.hasFocus() || forceText) stringSec1.textInput.text = '${Math.round(sliderSec1.value * 255)}';
		if (!stringSec2.textInput.hasFocus() || forceText) stringSec2.textInput.text = '${Math.round(sliderSec2.value * 255)}';
		if (!stringAlpha.textInput.hasFocus() || forceText) stringAlpha.textInput.text = '${Math.round(sliderAlpha.value * 255)}';
		if (!colorHex.textInput.hasFocus() || forceText) colorHex.textInput.text = '${StringTools.hex(color.toInt(true), 8)}';

		sliderSec0.refreshTexture();
		sliderSec1.refreshTexture();
		sliderSec2.refreshTexture();
		sliderAlpha.refreshTexture();
	}

	function syncColorPreview(newColor: hrt.impl.ColorSpace.Color) {
		if (preview.huiBg == null) preview.backgroundType = "hui";
		preview.huiBg.background = newColor.toInt(false) | 0xFF000000;
		if (previewAlpha.huiBg == null) previewAlpha.backgroundType = "hui";
		previewAlpha.huiBg.background = newColor.toInt(true);
	}

	public dynamic function onValueChanged(isTemporary: Bool) {}
}

enum ColorSliderOrientation {
	Horizontal;
	Vertical;
	Both;
}

class HuiColorSlider extends HuiElement {
	static var SRC = <hui-color-slider>
	</hui-color-slider>;

	static final gradientTextureSize = 32;
	static var tempColorVec = new h3d.Vector4();
	static var tempColor = new hrt.impl.ColorSpace.Color();

	/**Indicate if the color slider is a one or two dimentional slider**/
	@:p public var orientation(default, set) : ColorSliderOrientation = Horizontal;

	public var value(default, set) : Float = 0;

	/**Contains the Y component when the orientation is in Both mode**/
	public var value2(default, set) : Float = 0;

	var gradientTexture : h3d.mat.Texture;
	var gradientPixels : hxd.Pixels;

	public var indicatorDirty = false;
	var posIndicator : h2d.Graphics;

	public function new(?parent) {
		super(parent);
		initComponent();

		backgroundType = "hui";

		alloc();

		this.makeInteractive();
		this.interactive.onPush = function(e) {
			if(e.button != 0)
				return;
			setValuesFromMouse(e.relX, e.relY);
			onChange(true);
			this.interactive.getScene().startCapture(function(e){
				if (e.kind == EMove) {
					setValuesFromMouse(e.relX - this.absX, e.relY - this.absY);
					onChange(true);
				}
				if (e.kind == ERelease) {
					this.interactive.getScene().stopCapture();
					onChange(false);
				}
			});
		}

		posIndicator = new h2d.Graphics(this);
		// Doesn't seems to work a the moment
		//posIndicator.addShader(new PreviewShaderAlpha());

		indicatorDirty = true;

		this.onAfterReflow = () -> {
			indicatorDirty = true;
		}
	}

	public function refreshTexture() {
		for (j in 0...gradientPixels.height) {
			for (i in 0...gradientPixels.width) {
				var x = i / (gradientTextureSize - 1);
				var y = j / (gradientTextureSize - 1);

				var value = orientation != Vertical ? x : y;
				var value2 = orientation != Vertical ? y : x;

				getColor(value, value2, tempColorVec);
				gradientPixels.setPixelF(i, j, tempColorVec);
			}
		}
		gradientTexture.uploadPixels(gradientPixels);
		indicatorDirty = true;
	}

	public dynamic function getColor(value: Float, value2: Float, color: h3d.Vector4) : Void {
		color.x = value;
		color.y = value2;
		color.z = 0;
		color.a = 1;
	}

	public dynamic function onChange(isTemporary: Bool) : Void {}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);

		if (indicatorDirty)
			updatePosIndicator();
	}

	override function onRemove() {
		super.onRemove();
		cleanupAllocs();
	}

	function set_orientation(newOrientation: ColorSliderOrientation) : ColorSliderOrientation {
		if (newOrientation != orientation) {
			orientation = newOrientation;
			alloc();
		}
		return orientation;
	}

	function set_value(v: Float) : Float {
		indicatorDirty = true;
		return value = v;
	}

	function set_value2(v: Float) : Float {
		indicatorDirty = true;
		return value2 = v;
	}

	function cleanupAllocs() {
		if (gradientTexture != null) {
			gradientTexture.dispose();
			gradientTexture = null;
		}
		if (gradientPixels != null) {
			gradientPixels.dispose();
			gradientPixels = null;
		}
	}

	function alloc() {
		cleanupAllocs();
		var texWidth = orientation != Vertical ? gradientTextureSize : 1;
		var texHeight = orientation != Horizontal ? gradientTextureSize : 1;
		gradientTexture = new h3d.mat.Texture(texWidth, texHeight, [Dynamic]);
		gradientTexture.filter = Linear;
		gradientPixels = hxd.Pixels.alloc(texWidth, texHeight, RGBA);

		this.huiBg.imageMode = Stretch;
		var tile = h2d.Tile.fromTexture(gradientTexture);
		tile.setPosition(0.5,0.5);
		tile.setSize(gradientTextureSize - 1.0 , gradientTextureSize - 1.0);
		this.huiBg.imageTile = tile;

		refreshTexture();
	}

	function setValuesFromMouse(mouseX : Float, mouseY : Float) {
		var x = hxd.Math.clamp(mouseX / this.calculatedWidth, 0, 1);
		var y = hxd.Math.clamp(mouseY / this.calculatedHeight, 0, 1);

		value2 = 0;

		switch(orientation) {
			case Horizontal:
				value = x;
			case Vertical:
				value = y;
			case Both:
				value = x;
				value2 = y;
		}
	}

	function updatePosIndicator() {
		var x = orientation != Vertical ? value : 0.5;
		var y = orientation == Horizontal ? 0.5 : (orientation == Vertical ? value : value2);

		// in some color spaces like XYZ the values can get out of bounds
		x = hxd.Math.clamp(x, 0, 1.0);
		y = hxd.Math.clamp(y, 0, 1.0);

		posIndicator.x = hxd.Math.round(x * calculatedWidth);
		posIndicator.y = hxd.Math.round(y * calculatedHeight);
		posIndicator.clear();
		var currentColor = tempColorVec;
		getColor(value, value2, currentColor);
		var intColor = currentColor.toColor();

		function drawIndicator() {
			final indicatorWidth = 12;
			final hWidth = indicatorWidth/ 2;

			switch(orientation) {
				case Horizontal:
					posIndicator.drawRect(x - hWidth, - innerHeight / 2, indicatorWidth, innerHeight);
				case Vertical:
					posIndicator.drawRect(- innerWidth / 2, y - hWidth, innerWidth, indicatorWidth);
				case Both:
					posIndicator.drawRect(- hWidth, - hWidth, indicatorWidth, indicatorWidth);
			}
		}

		posIndicator.beginFill(intColor /*, currentColor.a / 255.0*/);
		drawIndicator();

		posIndicator.endFill();

		tempColor.load(intColor, true);
		var hsl = hrt.impl.ColorSpace.iRGBtoHSV(tempColor, tempColorVec);

		var outlineColor = 0;
		if (hsl.z /* lightness*/  < 0.51) {
			outlineColor = 0xFFFFFFFF;
		}

		posIndicator.lineStyle(1, outlineColor, 1.0);
		drawIndicator();

		indicatorDirty = false;
	}
}
#end
