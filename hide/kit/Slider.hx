package hide.kit;

#if domkit

class Slider<T:Float> extends Widget<T> {
	/**
		If set, the slider won't go bellow the given value
	**/
	public var min(default, set) : Null<T> = null;

	/**
		If set, the slider won't go above the given value
	**/
	public var max(default, set) : Null<T> = null;

	/**
		Override the default step for editing the curve. Note that if min and max are set the step will be calculated accordingly, but setting
		this will override the automaticaly calculated value.
	**/
	public var step : Null<T> = null;

	/**
		If set, the slider will use an exponential curve (e^x) for editing values.
	**/
	public var exp : Bool = false;

	/**
		If set, the slider will use a polynomial curve (x^n) for editing values.
		if true, n will be equal to 2, if set to a float, n will be equal to that float instead
	**/
	public var poly : Dynamic = false;

	/**
		If true, when the user reaches the min or max value, the value will wrap to the max / min value respectively
	**/
	public var wrap: Bool = false;

	/**
		If set, the value of this slider will be rounded to the nearest int
	**/
	public var int : Bool = false;


	#if js
	var slider: js.html.InputElement;
	#else
	var slider: hrt.ui.HuiSlider;
	#end

	var showRange: Bool = false;
	var subPixelSlide : Float = 0;
	var startValueLinear : Float = 0;
	var expScale : Null<Float> = null;
	var polyScale : Null<Float> = null;

	function parseScaleParam(param: Dynamic, def: Float) : Null<Float>  {
		if (param is Bool) {
			if (param == false)
				return null;
			return def;
		} else if (param is Float || param is Int) {
			return cast param;
		} else if (param is String) {
			return Std.parseFloat(param);
		} else {
			throw "unknown type";
		}
		return null;
	}

	function makeInput() : NativeElement {
		expScale = parseScaleParam(exp, 1.2);
		polyScale = parseScaleParam(poly, 2.0);

		if (expScale != null && polyScale != null) {
			throw "Slider can't be both exp and poly";
		}

		#if js
		var container = js.Browser.document.createElement("kit-slider");
		slider = js.Browser.document.createInputElement();
		container.append(slider);

		slider.title = "Shift : Precise movement\nCtrl : Fast Movement";

		var capture = false;
		var hasMoved = false;
		var ignoreMoveEvents = 2;
		slider.addEventListener("pointerdown", (e: js.html.PointerEvent) -> {
			if (e.button != 0)
				return;

			e.preventDefault();
			e.stopPropagation();

			slider.setPointerCapture(e.pointerId);
			slider.requestPointerLock();
			subPixelSlide = 0;
			startValueLinear = valueToLinear(value);
			capture = true;
			hasMoved = false;
			ignoreMoveEvents = 2;
		});

		slider.addEventListener("pointermove", (e: js.html.PointerEvent) -> {
			if (!capture)
				return;

			// Ignore nth move events to remove some weirdness with display scaling
			if (ignoreMoveEvents > 0) {
				ignoreMoveEvents--;
				return;
			}

			e.preventDefault();
			e.stopPropagation();



			var min = min != null ? valueToLinear(min) : null;
			var max = max != null ? valueToLinear(max) : null;

			var mult : Float = int ? null : step;
			if (min != null && max != null && mult == null) {
				mult = (max - min) / 1000.0;
			}
			if (mult == null) {
				if (int) {
					mult = 0.01 * (step ?? 1.0);
				} else {
					mult = 0.01;
				}
			}
			if (e.ctrlKey) mult *= 10.0;
			if (e.shiftKey) mult /= 10.0;

			subPixelSlide += e.movementX / js.Browser.window.devicePixelRatio * mult;

			var newValueLinear = startValueLinear + subPixelSlide;

			if (wrap && min != null && max !=null) {
				var size = max - min;
				newValueLinear = ((newValueLinear - min + size) % size) + min;
			} else {
				if (min != null)
					newValueLinear = hxd.Math.max(newValueLinear, min);
				if (max != null)
					newValueLinear = hxd.Math.min(newValueLinear, max);
			}

			subPixelSlide = newValueLinear - startValueLinear;

			slideTo(cast linearToValue(newValueLinear), true);
			hasMoved = true;
		});

		slider.addEventListener("pointerup", (e: js.html.PointerEvent) -> {
			if (!capture)
				return;

			e.preventDefault();
			e.stopPropagation();
			capture = false;
			slider.ownerDocument.exitPointerLock();

			if (!hasMoved) {
				slider.focus();
				slider.select();
			} else {
				slideTo(value, false);
			}
		});

		var inputSave = null;
		slider.addEventListener("focus", (e: js.html.InputEvent) -> {
			inputSave = slider.value;
		});

		slider.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.key == "Enter") {
				e.preventDefault();
				e.stopPropagation();
				slider.blur();
			} else if (e.key == "Escape") {
				e.preventDefault();
				e.stopPropagation();
				if (inputSave != null)
					slider.value = inputSave;
				inputSave = null;
				slider.blur();
			}
		});

		slider.addEventListener("input", (e: js.html.InputEvent) -> {
			var newValue = Std.parseFloat(slider.value);
			if (newValue != null) {
				broadcastValueChange(true);
			}
		});

		slider.addEventListener("blur", (e: js.html.FocusEvent) -> {
			var newValue = Std.parseFloat(slider.value);
			slideTo(cast newValue ?? value, false);
		});

		return container;
		#else
		// slider = new hrt.ui.HuiSlider();
		// slider.slider.onChange = () -> {
		// 	value = slider.slider.value;
		// 	broadcastValueChange(true);
		// }
		// slider.slider.minValue = -10;
		// slider.slider.maxValue = 10;
		// return slider;
		return null;
		#end
	}

	function snap(value: Float) : T {
		var snap : Float = (step:Float) ?? (int ? 1.0 : 0.01);
		return cast hxd.Math.round(value / snap) * snap;
	}

	function slideTo(newValue: T, isTemporary: Bool) {
		var group = Std.downcast(parent, SliderGroup);
		newValue = snap(newValue);

		if (group != null && group.isLocked) {
			var changeDelta : Float = (newValue:Float) / (value:Float);

			var sliders : Array<Widget<Dynamic>> = [];
			for (sibling in parent.children) {
				var siblingSlider = Std.downcast(sibling, Slider);
				if (siblingSlider == null)
					continue;

				if (Math.isFinite(changeDelta)) {
					siblingSlider.value = cast snap(changeDelta * siblingSlider.value);
				} else {
					// if we divided by zero, just set the value to be equal to the new one
					siblingSlider.value = cast newValue;
				}

				sliders.push(siblingSlider);
			}

			propagateChange(Value(sliders, isTemporary));
		}
		else {
			value = newValue;
			broadcastValueChange(isTemporary);
		}
	}

	inline function set_min(v) {
		min = v;
		syncValueUI();
		return v;
	}

	inline function set_max(v) {
		max = v;
		syncValueUI();
		return v;
	}

	function linearToValue(v: Float) : Float {
		if (expScale != null)
			return hxd.Math.pow(expScale, v);
		if (polyScale != null)
			return hxd.Math.pow(v, polyScale);
		return v;
	}

	function valueToLinear(v:Float) : Float {
		if (expScale != null)
			return hxd.Math.logBase(v, expScale);
		if (polyScale != null)
			return hxd.Math.pow(v, 1.0/polyScale);
		return v;
	}

	override function customIndeterminate():Bool {
		return true;
	}

	override function syncValueUI() {
		if (slider == null)
			return;

		if (isIndeterminate()) {
			#if js
			slider.value = "---";
			#end
			return;
		}
		#if js
		slider.value = Std.string(hxd.Math.round(value * 100) / 100);
		#else
		slider.slider.value = value;
		#end

		if (showRange && min != null && max != null) {
			var min : Float = valueToLinear(min);
			var max : Float = valueToLinear(max);
			var value : Float = valueToLinear(value);

			var alpha = hxd.Math.clamp((value - min) / (max - min)) * 100;
			#if js
			slider.style.background = 'linear-gradient(to right, var(--range-fill) ${alpha}%, var(--widget-bg) ${alpha}%)';
			#end
		} else {
			#if js
			slider.style.background = null;
			#end
		}
	}

	function getDefaultFallback() : T {
		return cast 0;
	}

	function stringToValue(obj: String) : Null<T> {
		var unser = Std.parseFloat(obj);
		if (Math.isNaN(unser))
			return null;
		return cast unser;
	}
}

#end