package hide.comp;

import hrt.impl.ColorSpace;
import h2d.Slider;
import js.html.InputElement;
import js.jquery.Event;
import nw.Clipboard;
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

	public var value(get, set) : Int;
	var workValue : Int;

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

		if (fieldName != null)
			e.attr( { "field":fieldName});

		if (root != null) root.replaceWith(e) else root = e;
		super(parent, e);
		this.canEditAlpha = canEditAlpha;
		this.isPickerEnabled = inIsPickerEnabled;

		element.click(function(e) {
			if (picker == null && isPickerEnabled) {
				picker = new ColorPicker(canEditAlpha, null, this.element);
				picker.value = workValue;
				picker.onChange = function(isDragging) {
					workValue = picker.value;
					repaint();
					onChange(isDragging);
				};
				picker.onClose = function() {
					picker.onClose = function(){};
					picker.onChange = function(e){};
					picker = null;
				}

				onPickerOpen();
			} else if (picker != null) {
				picker.close();
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

	public var value(get, set) : Int;
	var workValue : Int;
	var mask : Int;

	var primarySliders : SliderGroup;
	var secondarySliders : SliderGroup;

	var colorCode : Element;
	var preview : ColorBox;

	var pasteButton : Element;
	var copyButton : Element;

	var canEditAlpha : Bool;

	var width = 256;
	var height = 256;

	var valueChangeGuard : Int = 0;

	public var valueToARGB : (value : Vector4,  outColor : Color) -> Color;
	public var ARGBToValue : (color : Color, outVector: Vector4) -> Vector4;

	public function repaint() {

		primarySliders.value = workValue;
		secondarySliders.value = workValue;
		colorCode.val(StringTools.hex(workValue, if(canEditAlpha) 8 else 6));
		preview.value = workValue;
	}

	public function change(isDragging:Bool) {
		repaint();
		valueChangeGuard += 1;
		onChange(isDragging);
		valueChangeGuard -= 1;
	}

	public function test() {
		// Test that HSVtoiRGB -> iRGBToHSV produces the same color in input as output
		var colorCol = new Color();
		var colorCol2 = new Color();

		for (i in 0...0xFFFFFF) {
			colorCol.r = (i >> 16) & 0xFF;
			colorCol.g = (i >> 8) & 0xFF;
			colorCol.b = (i >> 0) & 0xFF;
			var colorVec = ColorSpace.iRGBtoHSV(colorCol);

			ColorSpace.HSVtoiRGB(colorVec, colorCol2);

			if (colorCol.r != colorCol2.r ||
				colorCol.g != colorCol2.g ||
				colorCol.b != colorCol2.b)
			{
				trace("Missmatch found for 0x" + StringTools.hex(i), colorCol, colorCol2);
			}
		}

	}

	public function new( ?canEditAlpha : Bool = false, ?parent : Element, ?root : Element ) {
		if( root == null ) root = new Element("<div>").addClass("input-color");
		super(parent,root);
		this.canEditAlpha = canEditAlpha;


		popup.addClass("color-picker");

		valueToARGB = ColorSpace.HSVtoiRGB;
		ARGBToValue = ColorSpace.iRGBtoHSV;

		initSliders();

		new Element("<hr>").appendTo(popup);

		initInfobar();

		reflow();
		repaint();
	}

	function initInfobar() {
		var infoBar = new Element("<div>").addClass("info-bar");
		popup.append(infoBar);

		preview = new ColorBox(infoBar, null, false, canEditAlpha);
		preview.element.width(64);
		preview.element.height(64);

		var inputRow = new Element("<div>");
		infoBar.append(inputRow);

		inputRow.append(new Element("<span>").html("#"));

		colorCode = new Element("<input type='text' maxlength='9'>").css({display: "inline-block", width:"70px"}).change(
			function(e : Event) {
				var color = getColorFromString(cast(e.target,InputElement).value);
				if (color != null) {
					set_value(color);
					change(false);
				}
				else {
					repaint(); // we refresh to reset the text of the input to the current color if the input is invalid
				}
			}
		);

		// Selecting the text of the colorCode with the mouse can
		// close the popup if we release the mouse outside the popup.
		// These event handlers prevent this
		var colorCodeElem = colorCode.get(0);
		colorCodeElem.onpointerdown = function(e : js.html.PointerEvent) {
			colorCodeElem.setPointerCapture(e.pointerId);
		}

		colorCodeElem.onpointerup = function(e : js.html.PointerEvent) {
			colorCodeElem.releasePointerCapture(e.pointerId);
		}
		inputRow.append(colorCode);

		inputRow.addClass("hide-toolbar2");
		inputRow.css({'margin-bottom': 'auto'});

		var group = new Element("<div class='tb-group'>").appendTo(inputRow);
		copyButton = new Element("<div class='button2' title='Copy'>");
		copyButton.append(new Element("<div class='icon ico ico-copy'>"));
		copyButton.on("click", function(e) {
			Clipboard.get().set(colorCode.val());
		});
		group.append(copyButton);


		pasteButton = new Element("<div class='button2' title='Paste'>");
		pasteButton.append(new Element("<div class='icon ico ico-paste'>"));
		pasteButton.on("click", function(e) {
			var value = Clipboard.get().get();
			colorCode.val(value).change();
		});
		group.append(pasteButton);

	}

	function initSliders() {
		{
			primarySliders = new SliderGroup(popup, canEditAlpha, ColorSpace.colorModes[1]);

			primarySliders.onChange = function(isDragging : Bool) {
				workValue = primarySliders.value;
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

		new Element("<hr>").appendTo(popup);

		{
			secondarySliders = new SliderGroup(popup, canEditAlpha, ColorSpace.colorModes[0]);

			secondarySliders.onChange = function(isDragging : Bool) {
				workValue = secondarySliders.value;
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

			var components = new Array<ColorSliderComponent>();
			components.push(addRow(new Vector4(1.0,0.0,0.0,0.0), secondarySliders, false));
			components.push(addRow(new Vector4(0.0,1.0,0.0,0.0), secondarySliders, false));
			components.push(addRow(new Vector4(0.0,0.0,1.0,0.0), secondarySliders, false));
			if (canEditAlpha) {
				components.push(addRow(new Vector4(0.0,0.0,0.0,1.0), secondarySliders, true));
			}


			function changeColorMode(colorMode : ColorMode) {
				secondarySliders.setColorMode(colorMode, value);

				for (i => comp in components) {
					if (i < 3) {
						comp.label.text(colorMode.name.charAt(i));
					}
					else {
						comp.label.text("A");
					}
				}
			}

			var initialMode : Int = ide.currentConfig.get("colorPicker.secondaryColorMode", 0);
			var modeSelect = new Element("<select id=secondary-color-mode>").css("align-self", "end").appendTo(vbox);
			for (i => mode in ColorSpace.colorModes) {
				var option = new Element("<option>").val(i).text(mode.name).appendTo(modeSelect);
				if (i == initialMode)
					option.attr("selected", "true");
			}

			modeSelect.change(
				function(e : Event) {
					var val = Std.parseInt(modeSelect.val());
					var modeIndex : Int = Std.int(hxd.Math.clamp(val, 0, ColorSpace.colorModes.length));
					ide.currentConfig.set("colorPicker.secondaryColorMode", modeIndex);
					changeColorMode(ColorSpace.colorModes[modeIndex]);
				}
			);

			changeColorMode(ColorSpace.colorModes[initialMode]);
		}
	}

	public dynamic function onChange(isDragging) {
	}

	function getColorFromString(str:String) : Null<Int> {
		if (str.charAt(0) == "#")
			str = str.substr(1);

		var color = Std.parseInt("0x"+str);
		if (color == null)
			return null;

		var containsAlpha = false;
		switch (str.length) {
			case 2: // Assume color is shade of gray
				color = (color << 16) + (color << 8) + (color);
			case 3: // handle #XXX html codes
				var r = (color >> 8) & 0xF;
				var g = (color >> 4) & 0xF;
				var b = (color >> 0) & 0xF;
				color = (r << 20) + (r << 16) + (g << 12) + (g << 8) + (b << 4) + (b << 0);
			case 6:
			case 8:
				containsAlpha = true;
			default:
				return null;
		}

		if (!containsAlpha && canEditAlpha) {
			color = (color) + (0xFF << 24);
		}
		else if (containsAlpha && !canEditAlpha) {
			color = (color & 0xFFFFFF) ;
		}

		return color;
	}

	function get_value() {
		return workValue;
		//var color = new Color();
		//valueToARGB(currentValue, color);
		//return if (!canEditAlpha) (color.r << 16) + (color.g << 8) + color.b
		//else (color.r << 16) + (color.g << 8) + (color.b << 0) + (color.a << 24);
	};

	function set_value(v) {
		if (valueChangeGuard == 0) {
			workValue = v;

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

	public var colorMode : ColorMode;

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

		canvas = Browser.document.createCanvasElement();

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
		var c2d = canvas.getContext("2d");

		var image_data = c2d.getImageData(0,0,canvas.width,canvas.height);
		var value : Vector4 = new Vector4();
		var color : Color = new Color();

		for (y in 0...canvas.height) {
			for (x in 0...canvas.width) {
				var index = (y*canvas.width + x) * 4;
				getColorAtPixelDisplay(x*canvasDownsample,y*canvasDownsample, value);
				colorMode.valueToARGB(value, color);
				image_data.data[index] = Std.int(color.r);
				image_data.data[index+1] = Std.int(color.g);
				image_data.data[index+2] = Std.int(color.b);
				image_data.data[index+3] = Std.int(color.a);
			}
		}

		c2d.putImageData(image_data,0,0);

		var cursorPos = getCursorPos();
		selectionCursor.attr("transform", 'translate(${cursorPos.x}, ${cursorPos.y})');

		getColorAtPixelDisplay(cursorPos.x,cursorPos.y, value);
		colorMode.valueToARGB(workValue, color);
		selectionColor.css({"fill": 'rgba(${color.r}, ${color.g}, ${color.b}, ${color.a/255.0})'});

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
	public var value(get,set) : Int;
	public var workValue : Vector4 = new Vector4();
	var valueChangeLock : Int = 0;

	var colorMode : ColorMode;

	public function setColorMode(colorMode : ColorMode, value : Int) {
		this.colorMode = colorMode;
		for (slider in sliders) {
			slider.colorMode = colorMode;
		}
		this.value = value;
	}

	public function new(parent : Element, canEditAlpha : Bool, colorMode : ColorMode) {
		var root = new Element("<div>").addClass("slider-container");
		super(parent, root);

		this.colorMode = colorMode;

		this.canEditAlpha = canEditAlpha;
	}

	public dynamic function onChange(isDragging : Bool) {

	}

	function set_value(v : Int) : Int {
		if (valueChangeLock == 0) {
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

			workValue = colorMode.ARGBToValue(color, null);
		}

		repaint();
		return get_value();
	}

	function get_value() {
		var color = new Color();
		colorMode.valueToARGB(workValue, color);
		return if (!canEditAlpha) (color.r << 16) + (color.g << 8) + color.b
		else (color.r << 16) + (color.g << 8) + (color.b << 0) + (color.a << 24);
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