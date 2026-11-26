package hide.comp;

import hrt.impl.ColorSpace.Color;
import hrt.impl.ColorSpaceF;
import h2d.Slider;
import js.html.InputElement;
import js.jquery.Event;
import electron.Clipboard;
import js.html.PointerEvent;
import h3d.Vector4;
import js.Browser;

// Displays a color with its alpha component. Can open a color picker on click
class ColorBox extends Component {

	public var picker : ColorPicker;

	var preview : Element;
	var previewWithAlpha : Element;
	var canEditAlpha : Bool = false;
	public var isPickerEnabled : Bool = false;

	/** Below the color box when null **/
	public var popupAnchor : Popup.Anchor;

	public var value(get, set) : Int;
	var workValue : Int;

	var startValue : Int;

	public function isPickerOpen() : Bool {
		return picker != null;
	}

	function set_value(value:Int) {
		workValue = value;
		if (picker != null) picker.value = workValue;
		repaint();
		return get_value();
	}

	function get_value() {
		return workValue;
	}

	public dynamic function onChange(isDragging : Bool) {

	}

	public dynamic function onPickerOpen() {

	}

	public function new(?parent : Element, ?root : Element, inIsPickerEnabled:Bool, canEditAlpha:Bool = false, ?fieldName : String) {
		var e = new Element("<div>").addClass("color-box").width("32px").height("24px").addClass("checkerboard-bg");
		if (root != null)
			hide.comp.JsTools.copyAttributes(e, root);

		if (root != null) root.replaceWith(e) else root = e;
		super(parent, e);
		this.canEditAlpha = canEditAlpha;
		this.isPickerEnabled = inIsPickerEnabled;

		element.click(function(e) {
			if (picker == null && isPickerEnabled) {
				picker = new ColorPicker(canEditAlpha, this.element);
				if (popupAnchor != null)
					picker.anchor = popupAnchor;
				picker.value = workValue;
				startValue = workValue;
				picker.onChange = function(isDragging) {
					workValue = picker.value;
					repaint();
					onChange(true);
				};
				picker.onClose = function() {
					workValue = (picker.wasCancelled && ide.currentConfig.get("hide.colorPickerEscUndo")) ? startValue : picker.value;
					repaint();
					onChange(false);
					picker.onClose = function(){};
					picker.onChange = function(e){};
					picker = null;
				}

				onPickerOpen();
			} else if (picker != null) {
				//picker.close();
			}
		});

		preview = new Element("<div>").width("50%").height("100%").css({display:"inline-block"});
		element.append(preview);

		previewWithAlpha = new Element("<div>").width("50%").height("100%").css({display:"inline-block"});
		element.append(previewWithAlpha);
	}

	function repaint() {
		var v = value;

		var color : Color = if (!canEditAlpha) new Color(
			(v >> 16) & 0xFF,
			(v >> 8) & 0xFF,
			(v >> 0) & 0xFF,
			255);
		else new Color(
			(v >> 16) & 0xFF,
			(v >> 8) & 0xFF,
			(v >> 0) & 0xFF,
			(v >> 24) & 0xFF
		);

		preview.css({"background-color": 'rgb(${color.r}, ${color.g}, ${color.b})'});
		previewWithAlpha.css({"background-color": 'rgba(${color.r}, ${color.g}, ${color.b}, ${color.a/255.0})'});
	}
}

typedef ColorSliderComponent = {label:Element};


class ColorPicker extends Popup {

	var startValue: Int;
	public var value(get, set) : Int;

	/** Color in `colorMode` space, alpha in w **/
	var workValue = new Vector4();
	var colorMode = ColorSpaceF.colorModes[0];
	var primaryMode = ColorSpaceF.colorModes[1];
	var tmpColor = new Vector4();
	var tmpValue = new Vector4();
	var mask : Int;

	var primarySliders : SliderGroup;
	var secondarySliders : SliderGroup;
	var components: Array<ColorSliderComponent>;

	var colorCode : InputElement;
	var preview : ColorBox;

	var canEditAlpha : Bool;

	var width = 256;
	var height = 256;

	var valueChangeGuard : Int = 0;

	public function repaint() {
		convert(workValue, colorMode, primaryMode, tmpValue);
		primarySliders.value = tmpValue;
		secondarySliders.value = workValue;
		colorCode.value = StringTools.hex(value, if(canEditAlpha) 8 else 6);
		preview.value = value;
	}

	function convert(v : Vector4, from : ColorModeF, to : ColorModeF, out : Vector4) {
		if (from == to)
			out.load(v);
		else
			to.fromRGBA(from.toRGBA(v, tmpColor), out);
	}

	public function change(isDragging:Bool) {
		repaint();
		valueChangeGuard += 1;
		onChange(isDragging);
		valueChangeGuard -= 1;
	}

	public function test() {
		// Test that RGBAtoHSV -> HSVtoRGBA produces the same color in input as output
		var colorVec = new Vector4();

		for (i in 0...0xFFFFFF) {
			colorVec.setColor(i);
			ColorSpaceF.RGBAtoHSV(colorVec, colorVec);
			var i2 = ColorSpaceF.HSVtoRGBA(colorVec, colorVec).toColor() & 0xFFFFFF;

			if (i != i2)
				trace("Missmatch found for 0x" + StringTools.hex(i), StringTools.hex(i2));
		}

	}

	public function new( ?canEditAlpha : Bool = false, ?parent : Element) {
		//if( root == null ) root = new Element("<div>").addClass("input-color");
		super(parent);
		this.canEditAlpha = canEditAlpha;


		element.addClass("color-picker");

		initSliders();

		new Element("<hr>").appendTo(element);

		initInfobar();

		reflow();
		repaint();
	}

	function changeColorMode(mode : ColorModeF) {
		convert(workValue, colorMode, mode, workValue);
		colorMode = mode;
		secondarySliders.setColorMode(colorMode, workValue);

		for (i => comp in components) {
			if (i < 3) {
				comp.label.text(colorMode.name.charAt(i));
			}
			else {
				comp.label.text("A");
			}
		}
	}

	function initInfobar() {
		var infoBar = new Element("<div>").addClass("info-bar");
		element.append(infoBar);

		preview = new ColorBox(infoBar, null, false, canEditAlpha);
		preview.element.width(64);
		preview.element.height(64);

		var hexColumn = Browser.document.createDivElement();
		hexColumn.className = "hex-column";
		infoBar.get(0).append(hexColumn);

		var inputRow = Browser.document.createDivElement();
		inputRow.className = "hex-input";
		hexColumn.append(inputRow);

		colorCode = Browser.document.createInputElement();
		colorCode.type = "text";
		colorCode.maxLength = 9;
		colorCode.onchange = function(e : Event) {
			var color = getColorFromString(colorCode.value);
			if (color != null) {
				set_value(color);
				change(false);
			}
			else {
				repaint(); // we refresh to reset the text of the input to the current color if the input is invalid
			}
		}

		// Selecting the text of the colorCode with the mouse can
		// close the popup if we release the mouse outside the popup.
		// These event handlers prevent this
		colorCode.onpointerdown = function(e : js.html.PointerEvent) {
			colorCode.setPointerCapture(e.pointerId);
		}

		colorCode.onpointerup = function(e : js.html.PointerEvent) {
			colorCode.releasePointerCapture(e.pointerId);
		}
		inputRow.append(colorCode);

		var toolbar = Browser.document.createDivElement();
		toolbar.className = "hide-toolbar2";
		hexColumn.append(toolbar);

		var group = Browser.document.createElement("hide-group");
		toolbar.append(group);

		function addButton(title : String, icon : String, onClick : () -> Void) {
			var button = hide.html.comp.Button.create();
			button.title = title;
			button.setAttribute("aria-label", title);
			button.icon = icon;
			button.onclick = (_) -> onClick();
			group.append(button);
		}

		addButton("Copy", Std.string(HideRes.icon.copy), () -> Clipboard.set(colorCode.value));

		addButton("Paste", Std.string(HideRes.icon.paste), () -> {
			colorCode.value = Clipboard.get();
			colorCode.dispatchEvent(new js.html.Event("change"));
		});

		addButton("Pick a color on screen", Std.string(HideRes.icon.eye_dropper), () -> {
			electron.Screen.pickColor().then(function(hex) {
				if (hex == null)
					return;
				var rgb = Std.parseInt("0x" + hex);
				set_value(canEditAlpha ? (value & 0xFF000000) | rgb : rgb);
				change(false);
			});
		});

		var initialMode : Int = ide.currentConfig.get("colorPicker.secondaryColorMode", 0);
		if (initialMode >= ColorSpaceF.colorModes.length)
			initialMode = 0;

		var modeSelect = hide.html.comp.Select.create();
		modeSelect.id = "secondary-color-mode";
		modeSelect.items = [for (i => mode in ColorSpaceF.colorModes) { label : mode.name, value : i }];
		modeSelect.value = initialMode;
		modeSelect.onValueChanged = () -> {
			var modeIndex : Int = modeSelect.value;
			ide.projectUserConfig.set("colorPicker.secondaryColorMode", modeIndex);
			changeColorMode(ColorSpaceF.colorModes[modeIndex]);
		};
		infoBar.get(0).append(modeSelect);

		changeColorMode(ColorSpaceF.colorModes[initialMode]);
	}

	function initSliders() {
		{
			primarySliders = new SliderGroup(element, canEditAlpha, primaryMode);

			primarySliders.onChange = function(isDragging : Bool) {
				convert(primarySliders.value, primaryMode, colorMode, workValue);
				change(isDragging);
			}

			primarySliders.addSlider(new ColorSlider(
				primarySliders.element,
				256,
				256,
				function(x : Int, y : Int, outVector : Vector4) {
					outVector.x = primarySliders.workValue.x;
					outVector.y = x / 255.0;
					outVector.z = 1.0-(y / 255.0);
					outVector.w = 1.0;
				},
				function(x : Int, y : Int, outVector : Vector4) {
					outVector.x = primarySliders.workValue.x;
					outVector.y = x / 255.0;
					outVector.z = 1.0-(y / 255.0);
					outVector.w = primarySliders.workValue.w;
				},
				function() : {x:Int, y:Int} {
					return {x: Std.int(primarySliders.workValue.y * 255.0), y: Std.int((1.0-primarySliders.workValue.z) * 255.0)};
				}));


			primarySliders.addSlider(new ColorSlider(
				primarySliders.element,
				1,
				256,
				function(x : Int, y : Int, outVector : Vector4) {
					outVector.x = y/255.0;
					outVector.y = 1.0;
					outVector.z = 1.0;
					outVector.w = 1.0;
				},
				function(x : Int, y : Int, outVector : Vector4) {
					outVector.r = y/255.0;
					outVector.g = primarySliders.workValue.y;
					outVector.b = primarySliders.workValue.z;
					outVector.w = primarySliders.workValue.w;
				},
				function() : {x:Int, y:Int} {
					return {x: 1, y: Std.int(primarySliders.workValue.x * 255.0)};
				}));

			if (canEditAlpha) {
				primarySliders.addSlider(new ColorSlider(
					primarySliders.element,
					1,
					256,
					function(x : Int, y : Int, outVector : Vector4) {
						outVector.x = primarySliders.workValue.x;
						outVector.y = primarySliders.workValue.y;
						outVector.z = primarySliders.workValue.z;
						outVector.w = y/255.0;
					},
					function(x : Int, y : Int, outVector : Vector4) {
						outVector.r = primarySliders.workValue.x;
						outVector.g = primarySliders.workValue.y;
						outVector.b = primarySliders.workValue.z;
						outVector.w = y/255.0;
					},
					function() : {x:Int, y:Int} {
						return {x: 1, y: Std.int(primarySliders.workValue.w * 255.0)};
					}));
			}
		}

		{
			secondarySliders = new SliderGroup(element, canEditAlpha, colorMode);

			secondarySliders.onChange = function(isDragging : Bool) {
				workValue.load(secondarySliders.value);
				change(isDragging);
			}

			var vbox = new Element("<div>").addClass("vbox").appendTo(secondarySliders.element);
			function addRow(mask : Vector4, group : SliderGroup, isAlpha : Bool) : ColorSliderComponent {
				var div = new Element("<div>").addClass("slider-value").appendTo(vbox);

				var slider = new ColorSlider(
					div,
					256,
					1,
					if (!isAlpha) function(x : Int, y : Int, outVector : Vector4) {
						var v = x / 255.0;
						outVector.x = mask.x * v + ((1.0 - mask.x) * group.workValue.x);
						outVector.y = mask.y * v + ((1.0 - mask.y) * group.workValue.y);
						outVector.z = mask.z * v + ((1.0 - mask.z) * group.workValue.z);
						outVector.w = 1.0;
					} else function(x : Int, y : Int, outVector : Vector4) {
						var v = x / 255.0;
						outVector.x = mask.x * v + ((1.0 - mask.x) * group.workValue.x);
						outVector.y = mask.y * v + ((1.0 - mask.y) * group.workValue.y);
						outVector.z = mask.z * v + ((1.0 - mask.z) * group.workValue.z);
						outVector.w = mask.w * v + ((1.0 - mask.w) * group.workValue.w);
					},
					function(x : Int, y : Int, outVector : Vector4) {
						var v = x / 255.0;
						outVector.x = mask.x * v + ((1.0 - mask.x) * group.workValue.x);
						outVector.y = mask.y * v + ((1.0 - mask.y) * group.workValue.y);
						outVector.z = mask.z * v + ((1.0 - mask.z) * group.workValue.z);
						outVector.w = mask.w * v + ((1.0 - mask.w) * group.workValue.w);
					},
					function() : {x:Int, y:Int} {
						var v = mask.x * group.workValue.x * 255 +
								mask.y * group.workValue.y * 255 +
								mask.z * group.workValue.z * 255 +
								mask.w * group.workValue.w * 255;
						return {x: Std.int(v), y: 1};
					}
				);

				group.addSlider(slider);

				var input = new Element("<input type='text' maxlength='4'>").appendTo(div).width(28);
				input.change(
					function(e : Event) {
						var val = Std.parseInt(input.val());
						if (val != null) {
							slider.pickColorAtPixel(val, 0);
						}
					}
				);

				slider.onRepaint = function() {
					var v = slider.getCursorPos().x;
					input.val(Std.string(v));
				}


				var name = new Element("<label>").appendTo(div);

				return {label:name};
			}

			components = new Array<ColorSliderComponent>();
			components.push(addRow(new Vector4(1.0,0.0,0.0,0.0), secondarySliders, false));
			components.push(addRow(new Vector4(0.0,1.0,0.0,0.0), secondarySliders, false));
			components.push(addRow(new Vector4(0.0,0.0,1.0,0.0), secondarySliders, false));
			if (canEditAlpha) {
				components.push(addRow(new Vector4(0.0,0.0,0.0,1.0), secondarySliders, true));
			}
		}
	}

	public dynamic function onChange(isDragging : Bool) {
	}

	function getColorFromString(str:String) : Null<Int> {
		return Color.intFromString(str, canEditAlpha);
	}

	function get_value() {
		var color = colorMode.toRGBA(workValue, tmpColor).toColor();
		return canEditAlpha ? color : color & 0xFFFFFF;
	};

	function set_value(v : Int) {
		if (!canEditAlpha)
			v &= 0xFFFFFF;

		// Skip the value read back from workValue, to keep its float precision
		if (valueChangeGuard == 0 && v != value) {
			tmpColor.setColor(v);
			if (!canEditAlpha)
				tmpColor.a = 1.0;
			colorMode.fromRGBA(tmpColor, workValue);

			repaint();
		}

		return get_value();
	}
}

class ColorSlider extends Component {
	public var value(get,set) : Vector4;

	function set_value(v : Vector4) {
		workValue = v;
		repaint();
		return v;
	}

	function get_value() : Vector4 {
		return workValue;
	}

	var workValue : Vector4;

	var width : Int;
	var height : Int;

	var canvas : js.html.CanvasElement;
	var svg : hide.comp.SVG;
	var gradient : Element;
	var selectionCursor : Element;
	var selectionColor : Element;

	var isDragging : Bool = false;

	var valueChangeLock : Int = 0;

	public var colorMode : ColorModeF;

	var getColorAtPixelDisplay : (x : Int, y : Int, outVector : Vector4) -> Void;
	var getColorAtPixel : (x : Int, y : Int, outVector : Vector4) -> Void;
	public var getCursorPos : () -> {x : Int, y : Int};

	var canvasDownsample = 8;

	public dynamic function onChange(isDragging : Bool) {

	}

	public dynamic function onRepaint() {

	}

	public function new(
		?parent : Element,
		width : Int,
		inHeight : Int,
		getColorAtPixelDisplay : (x : Int, y : Int, outVector : Vector4) -> Void,
		?getColorAtPixel : (x : Int, y : Int, outVector : Vector4) -> Void,
		getCursorPos : () -> {x : Int, y : Int}
		) {
		this.getColorAtPixelDisplay = getColorAtPixelDisplay;
		this.getColorAtPixel = if (getColorAtPixel != null) getColorAtPixel else getColorAtPixelDisplay;
		this.getCursorPos = getCursorPos;
		this.width = width;
		this.height = inHeight;

		var displayWidth = if(width > 1) width else 16;
		var displayHeight = if(height > 1) height else 16;

		var e = new Element("<div>").addClass("slider").addClass("checkerboard-bg").width(displayWidth).height(displayHeight);
		super(parent, e);

		canvas = element[0].ownerDocument.createCanvasElement();

		canvas.width = Std.int(Math.max(1, width / canvasDownsample));
		canvas.height = Std.int(Math.max(1, height / canvasDownsample));

		element.append(new Element(canvas));

		var svg = new SVG(element);
		svg.element.attr({viewBox: '0 0 $width $height'});

		selectionCursor = svg.group(svg.element);
		selectionColor = svg.circle(selectionCursor, 0,0, 8, {stroke:"white", "stroke-width": "2px"});
		svg.circle(selectionCursor, 0,0, 7, {stroke:"black", "stroke-width": "1px", fill: "none"});


		canvas.onpointerdown = function(event : js.html.PointerEvent) {
			isDragging = true;
			pickColorAtPixel(event.offsetX, event.offsetY);
			canvas.setPointerCapture(event.pointerId);
		}

		canvas.onpointerup = function(event : js.html.PointerEvent) {
			isDragging = false;
			pickColorAtPixel(event.offsetX, event.offsetY);
			canvas.releasePointerCapture(event.pointerId);
		}

		canvas.onpointermove = function(event : js.html.PointerEvent) {
			if (isDragging) {
				pickColorAtPixel(event.offsetX, event.offsetY);
			}
		}

		element.append(svg.element);
	}

	public function repaint() : Void {
		var c2d = canvas.getContext("2d", { willReadFrequently: true });

		var image_data = c2d.getImageData(0,0,canvas.width,canvas.height);
		var value : Vector4 = new Vector4();
		var color : Vector4 = new Vector4();

		for (y in 0...canvas.height) {
			for (x in 0...canvas.width) {
				var index = (y*canvas.width + x) * 4;
				getColorAtPixelDisplay(x*canvasDownsample,y*canvasDownsample, value);
				colorMode.toRGBA(value, color);
				image_data.data[index] = Math.round(color.r * 255);
				image_data.data[index+1] = Math.round(color.g * 255);
				image_data.data[index+2] = Math.round(color.b * 255);
				image_data.data[index+3] = Math.round(color.a * 255);
			}
		}

		c2d.putImageData(image_data,0,0);

		var cursorPos = getCursorPos();
		selectionCursor.attr("transform", 'translate(${cursorPos.x}, ${cursorPos.y})');

		getColorAtPixelDisplay(cursorPos.x,cursorPos.y, value);
		colorMode.toRGBA(workValue, color);
		selectionColor.css({"fill": 'rgba(${color.r * 255}, ${color.g * 255}, ${color.b * 255}, ${color.a})'});

		onRepaint();
	}

	public function pickColorAtPixel(x: Int, y : Int) {
		x = Std.int(Math.min(Math.max(0, x), width-1));
		y = Std.int(Math.min(Math.max(0, y), height-1));
		getColorAtPixel(x, y, workValue);
		change(isDragging);
	}

	public function change(isDragging : Bool) {
		valueChangeLock += 1;
		onChange(isDragging);
		valueChangeLock -= 1;
	}

}

class SliderGroup extends Component {

	public var sliders : Array<ColorSlider> = new Array<ColorSlider>();

	public var canEditAlpha : Bool = true;
	public var value(get,set) : Vector4;
	public var workValue : Vector4 = new Vector4();
	var valueChangeLock : Int = 0;

	var colorMode : ColorModeF;

	public function setColorMode(colorMode : ColorModeF, value : Vector4) {
		this.colorMode = colorMode;
		for (slider in sliders) {
			slider.colorMode = colorMode;
		}
		this.value = value;
	}

	public function new(parent : Element, canEditAlpha : Bool, colorMode : ColorModeF) {
		var root = new Element("<div>").addClass("slider-container");
		super(parent, root);

		this.colorMode = colorMode;

		this.canEditAlpha = canEditAlpha;
	}

	public dynamic function onChange(isDragging : Bool) {

	}

	function set_value(v : Vector4) : Vector4 {
		if (valueChangeLock == 0)
			workValue.load(v);

		repaint();
		return get_value();
	}

	function get_value() {
		return workValue;
	};

	public function addSlider(slider : ColorSlider) : ColorSlider {
		sliders.push(slider);
		slider.onChange = function(isDragging : Bool) {
			this.workValue = slider.value;
			change(isDragging);
		}
		slider.colorMode = colorMode;
		repaint();
		return slider;
	}

	public function repaint() {
		for (slider in sliders) {
			slider.value = workValue;
		}
	}

	public function change(isDragging : Bool) {
		repaint();
		valueChangeLock += 1;
		onChange(isDragging);
		valueChangeLock -= 1;
	}

}