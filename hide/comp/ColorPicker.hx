package hide.comp;

import nw.Window;
import h2d.filter.InnerGlow;
import js.html.Document;
import js.html.InputElement;
import js.jquery.Event;
import nw.Clipboard;
import js.node.ChildProcess;
import js.html.PointerEvent;
import format.abc.Data.ABCData;
import h3d.shader.ColorAdd;
import h3d.Vector;
import vdom.JQuery;
import js.Browser;

class Color {
	public var r : Int = 0;
	public var g : Int = 0;
	public var b : Int = 0;
	public var a : Int = 0;

	public function new(r:Int = 0, g:Int = 0, b:Int = 0, a:Int = 0) {
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
	}
}

// Displays a color with its alpha component. Can open a color picker on click
class ColorBox extends Component {

	var picker : ColorPicker;

	var preview : Element;
	var previewWithAlpha : Element;
	var canEditAlpha = false;

	public var value(get, set) : Int;
	var innerValue : Int;

	function set_value(value:Int) {
		innerValue = value;
		if (picker != null) picker.value = innerValue;
		repaint();
		return get_value();
	}

	function get_value() {
		return innerValue;
	}

	public dynamic function onChange(isDragging : Bool) {

	}

	public function new(?parent : Element, ?root : Element, isPickerEnabled:Bool, canEditAlpha:Bool = false) {
		var e = new Element("<div>").addClass("color-box").width("32px").height("24px").addClass("checkerboard-bg");
		if (root != null) root.replaceWith(e) else root = e;
		super(parent, e);
		this.canEditAlpha = canEditAlpha;
		
		if (isPickerEnabled) {
			element.click(function(e) {
				if (picker == null) {
					picker = new ColorPicker(canEditAlpha, null, this.element);
					picker.value = innerValue;
					picker.onChange = function(isDragging) {
						innerValue = picker.value;
						repaint();
						onChange(isDragging);
					};
					picker.onClose = function() {
						innerValue = picker.value;
						onChange(false);
						picker.onClose = function(){};
						picker.onChange = function(e){};
						picker = null;
					}
				} else {
					picker.close();
				}
			});
		}

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
			(v >> 24) & 0xFF,
			(v >> 16) & 0xFF,
			(v >> 8) & 0xFF,
			(v >> 0) & 0xFF
		);

		preview.css({"background-color": 'rgb(${color.r}, ${color.g}, ${color.b})'});
		previewWithAlpha.css({"background-color": 'rgba(${color.r}, ${color.g}, ${color.b}, ${color.a/255.0})'});
	}
}

class ColorPicker extends Component {

	public var value(get, set) : Int;
	var innerValue : Int;
	var mask : Int;

	var pickerPopup : Element;

	var gradient : ColorSlider;
	var hue : ColorSlider;
	var alpha : ColorSlider;

	var colorCode : Element;
	var preview : ColorBox;

	var pasteButton : Element;
	var copyButton : Element;

	var canEditAlpha : Bool;

	var initialValue : Vector;
	public var currentValue : Vector;

	var onMouseClickOutside : Dynamic;

	var width = 256;
	var height = 256;

	public var valueToRGBA : (value : Vector,  outColor : Color) -> Void;
	public var RGBAToValue : (color : Color) -> Vector;

	function iRGBtofRGB(color : Color) : Vector {
		return new Vector(color.r/255.0, color.g/255.0, color.b/255.0, color.a/255.0);
	}

	function fRGBtoiRGB(color : Vector, outColor : Color) {
		outColor.r = Std.int(color.r*255.0);
		outColor.g = Std.int(color.g*255.0); 
		outColor.b = Std.int(color.b*255.0);
		outColor.a = Std.int(color.a*255.0);
	}

	function iRGBtoHSV(color: Color) : Vector {
		var r = color.r / 255.0;
		var g = color.g / 255.0;
		var b = color.b / 255.0;
		var a = color.a / 255.0;

		var Cmax = Math.max(r, Math.max(g, b));
		var Cmin = Math.min(r, Math.min(g, b));
		var D = Cmax - Cmin;

		var H = if(D == 0) 0.0
				else if(Cmax == r) hxd.Math.ufmod((g - b)/D, 6) * 60.0
				else if (Cmax == g) ((b - r)/D + 2) * 60.0
				else ((r - g)/D + 4) * 60.0;
		
		H = H / 360.0;
		H = Math.min(Math.max(H, 0.0), 1.0);
		
		var S = if (Cmax == 0) 0 else D/Cmax;

		var V = Cmax;

		var A = a;

		return new Vector(H, S, V, A);
	}

	function HSVtoiRGB(hsv:Vector, outColor : Color) {
		var h = hsv.x * 360.0;
		var s = hsv.y;
		var v = hsv.z;

		var C = v * s;
		var X = C * (1 - Math.abs(hxd.Math.ufmod((h / 60.0),2) - 1));
		var m = v - C;

		var r = 0.0;
		var g = 0.0;
		var b = 0.0;

		if (h < 60) {r = C; g = X;} 
		else if (h < 120) {r = X; g = C;} 
		else if (h < 180) {g = C; b = X;} 
		else if (h < 240) {g = X; b = C;} 
		else if (h < 300) {r = X; b = C;} 
		else {r = C; b = X;};

		outColor.r = Std.int(Math.round((r+m)*255));
		outColor.g = Std.int(Math.round((g+m)*255));
		outColor.b = Std.int(Math.round((b+m)*255));
		outColor.a = Std.int(hsv.w * 255);
	}

	public function repaint() {
		gradient.repaint();
		hue.repaint();
		if (alpha!=null) alpha.repaint();
		

		var colorInt = get_value();
		colorCode.val(StringTools.hex(colorInt, if(canEditAlpha) 8 else 6));
		var color : Color = new Color();
		valueToRGBA(currentValue, color);
		preview.value = colorInt;
	}

	public function change(isDragging:Bool) {
		repaint();
		onChange(isDragging);
	}

	public function test() {
		// Test that HSVtoiRGB -> iRGBToHSV produces the same color in input as output
		var colorCol = new Color();
		var colorCol2 = new Color();

		for (i in 0...0xFFFFFF) {
			colorCol.r = (i >> 16) & 0xFF;
			colorCol.g = (i >> 8) & 0xFF;
			colorCol.b = (i >> 0) & 0xFF;
			var colorVec = iRGBtoHSV(colorCol);

			HSVtoiRGB(colorVec, colorCol2);

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

		currentValue = new Vector();

		pickerPopup = new Element("<div>").addClass("color-picker");


		//valueToRGBA = fRGBtoiRGB;
		//RGBAToValue = iRGBtofRGB;
		valueToRGBA = HSVtoiRGB;
		RGBAToValue = iRGBtoHSV;

		initSliders();
		initInfobar();

		var body = root.closest(".lm_content");
		if (body.length == 0) body = new Element("body");
		body.append(pickerPopup);

		onMouseClickOutside = function(e) {
			var elem = new Element(e.target);
			if (elem.closest(pickerPopup).length == 0 && elem.closest(element).length == 0) {
				close();
			}
		}

		Browser.document.addEventListener("click", onMouseClickOutside);

		var timer = new haxe.Timer(500);
		timer.run = function() {
			if( root.closest("body").length == 0 ) {
				timer.stop();
				close();
			}
		};

		reflow();
		repaint();
	}

	function reflow() {
		var offset = element.offset();
		var popupHeight = pickerPopup.get(0).offsetHeight;
		var popupWidth = pickerPopup.get(0).offsetWidth;

		var clientHeight = Browser.document.documentElement.clientHeight;
		var clientWidth = Browser.document.documentElement.clientWidth;

		offset.top += element.get(0).offsetHeight;
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 32);
		
		offset.left += element.get(0).offsetWidth;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 32);

		pickerPopup.offset(offset);
	}

	function initInfobar() {
		var infoBar = new Element("<div>").addClass("info-bar");
		pickerPopup.append(infoBar);

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
					onChange(false);
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

		inputRow.addClass("toolbar hide-toolbar");
		inputRow.css({'margin-bottom': 'auto'});

		copyButton = new Element("<div class='button' title='Copy'>");
		copyButton.append(new Element("<div class='icon ico ico-copy'>"));
		copyButton.on("click", function(e) {
			Clipboard.get().set(colorCode.val());
		});
		inputRow.append(copyButton);


		pasteButton = new Element("<div class='button' title='Paste'>");
		pasteButton.append(new Element("<div class='icon ico ico-paste'>"));
		pasteButton.on("click", function(e) {
			var value = Clipboard.get().get();
			colorCode.val(value).change();
		});
		inputRow.append(pasteButton);

	}

	function initSliders() {
		var sliders = new Element("<div>").addClass("checkerboard-bg").addClass("slider-container");
		pickerPopup.append(sliders);

		gradient = new ColorSlider(this,
			function(x : Int, y : Int, outVector : Vector) {
				outVector.x = currentValue.x;
				outVector.y = x / 255.0;
				outVector.z = y / 255.0;
				outVector.w = 1.0;
			},
			function(x : Int, y : Int, outVector : Vector) {
				outVector.x = currentValue.x;
				outVector.y = x / 255.0;
				outVector.z = y / 255.0;
				outVector.w = currentValue.w;
			}, 
			function() : {x:Int, y:Int} {
				return {x: Std.int(currentValue.y * 255.0), y: Std.int(currentValue.z * 255.0)};
			},
			256,256, sliders, null);
		sliders.append(gradient.element);

		hue = new ColorSlider(this,
			function(x : Int, y : Int, outVector : Vector) {
				outVector.x = y/255.0;
				outVector.y = 1.0;
				outVector.z = 1.0;
				outVector.w = 1.0;
			},
			function(x : Int, y : Int, outVector : Vector) {
				outVector.r = y/255.0;
				outVector.g = currentValue.y;
				outVector.b = currentValue.z;
				outVector.w = currentValue.w;
			},
			function() : {x:Int, y:Int} {
				return {x: 1, y: Std.int(currentValue.x * 255.0)};
			},1,256, sliders, null);
		sliders.append(hue.element);

		if (canEditAlpha) {
			alpha = new ColorSlider(this,
				function(x : Int, y : Int, outVector : Vector) {
					outVector.x = currentValue.x;
					outVector.y = currentValue.y;
					outVector.z = currentValue.z;
					outVector.w = y/255.0;
				},
				function(x : Int, y : Int, outVector : Vector) {
					outVector.r = currentValue.x;
					outVector.g = currentValue.y;
					outVector.b = currentValue.z;
					outVector.w = y/255.0;
				},
				function() : {x:Int, y:Int} {
					return {x: 1, y: Std.int(currentValue.w * 255.0)};
				},1,256, sliders, null);
			sliders.append(alpha.element);
		}
	}

	public function close() {
		var body = new Element("body");

		pickerPopup.remove();
		Browser.document.removeEventListener("click", onMouseClickOutside);
		onClose();
	}

	public dynamic function onClose() {
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
			color = (color << 8) + 0xFF;
		}
		else if (containsAlpha && !canEditAlpha) {
			color = (color >> 8);
		}

		return color;
	}

	function get_value() {
		var color = new Color();
		valueToRGBA(currentValue, color);
		return if (!canEditAlpha) (color.r << 16) + (color.g << 8) + color.b 
		else (color.r << 24) + (color.g << 16) + (color.b << 8) + color.a;	
	};

	function set_value(v) {
		var color : Color = if (!canEditAlpha) new Color(
			(v >> 16) & 0xFF,
			(v >> 8) & 0xFF,
			(v >> 0) & 0xFF,
			255);
		else new Color(
			(v >> 24) & 0xFF,
			(v >> 16) & 0xFF,
			(v >> 8) & 0xFF,
			(v >> 0) & 0xFF
		);

		currentValue = RGBAToValue(color);
		repaint();
		return get_value();
	}
}

class ColorSlider extends Component {
	public var picker : ColorPicker;

	var width : Int;
	var height : Int;

	var canvas : js.html.CanvasElement;
	var svg : hide.comp.SVG;
	var gradient : Element;
	var selectionCursor : Element;
	var selectionColor : Element;

	var isDragging : Bool = false;
	
	var getColorAtPixelDisplay : (x : Int, y : Int, outVector : Vector) -> Void;
	var getColorAtPixel : (x : Int, y : Int, outVector : Vector) -> Void;
	var getCursorPos : () -> {x : Int, y : Int};

	var canvasDownsample = 8;

	public function new(
		picker : ColorPicker, 
		getColorAtPixelDisplay : (x : Int, y : Int, outVector : Vector) -> Void,
		?getColorAtPixel : (x : Int, y : Int, outVector : Vector) -> Void,
		getCursorPos : () -> {x : Int, y : Int},
		width : Int, 
		inHeight : Int,
		?parent : Element, 
		?root : Element
		) {
		this.picker = picker;
		this.getColorAtPixelDisplay = getColorAtPixelDisplay;
		this.getColorAtPixel = if (getColorAtPixel != null) getColorAtPixel else getColorAtPixelDisplay; 
		this.getCursorPos = getCursorPos;
		this.width = width;
		this.height = inHeight;

		var displayWidth = if(width > 1) width else 16;
		var displayHeight = if(height > 1) height else 16;

		if (root == null) root = new Element("<div>").addClass("slider").width(displayWidth).height(displayHeight);
		super(parent, root);

		canvas = Browser.document.createCanvasElement();

		canvas.width = Std.int(Math.max(1, width / canvasDownsample));
		canvas.height = Std.int(Math.max(1, height / canvasDownsample));

		root.append(new Element(canvas));

		var svg = new SVG(element);
		svg.element.attr({viewBox: '0 0 $width $height'});

		selectionCursor = svg.group(svg.element);
		selectionColor = svg.circle(selectionCursor, 0,0, 8, {stroke:"white", "stroke-width": "2px"});
		svg.circle(selectionCursor, 0,0, 7, {stroke:"black", "stroke-width": "1px", fill: "none"});


		canvas.onpointerdown = function(event : js.html.PointerEvent) {
			pickColorAtPixel(event.offsetX, event.offsetY);
			isDragging = true;
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

		root.append(svg.element);
	}

	public function repaint() : Void {
		var c2d = canvas.getContext("2d");

		var image_data = c2d.getImageData(0,0,canvas.width,canvas.height);
		var value : Vector = new Vector();
		var conversionFunc = picker.valueToRGBA;
		var color : Color = new Color();

		for (y in 0...canvas.height) {
			for (x in 0...canvas.width) {
				var index = (y*canvas.width + x) * 4;
				getColorAtPixelDisplay(x*canvasDownsample,y*canvasDownsample, value);
				conversionFunc(value, color);
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
		conversionFunc(value, color);
		selectionColor.css({"fill": 'rgba(${color.r}, ${color.g}, ${color.b}, ${color.a/255.0})'});
	}

	public function pickColorAtPixel(x: Int, y : Int) {
		x = Std.int(Math.min(Math.max(0, x), width-1));
		y = Std.int(Math.min(Math.max(0, y), height-1));
		getColorAtPixel(x, y, picker.currentValue);
		picker.change(isDragging);
	}

}