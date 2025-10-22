package hide.kit;

class Slider<T:Float> extends Widget<T> {
	#if js
	var slider: js.html.InputElement;
	#else
	var slider: hrt.ui.HuiSlider;
	#end

	public var min(default, set) : Null<T> = null;
	public var max(default, set) : Null<T> = null;
	public var step : Null<T> = null;
	public var exp : Null<T> = null;
	public var wrap: Bool = false;
	var showRange: Bool = false;

	// set internally by the macro if the field is an Int
	var isInt : Bool = false;

	function makeInput() : NativeElement {
		#if js
		var container = js.Browser.document.createElement("kit-slider");
		slider = js.Browser.document.createInputElement();
		container.append(slider);

		var capture = false;
		var hasMoved = false;
		slider.addEventListener("pointerdown", (e: js.html.PointerEvent) -> {
			if (e.button != 0)
				return;

			e.preventDefault();
			e.stopPropagation();

			slider.setPointerCapture(e.pointerId);
			slider.requestPointerLock();
			capture = true;
			hasMoved = false;
		});

		slider.addEventListener("pointermove", (e: js.html.PointerEvent) -> {
			if (!capture)
				return;

			e.preventDefault();
			e.stopPropagation();

			var currentValue = value;

			var newValue : Float = value;
			var delta = e.movementX / js.Browser.window.devicePixelRatio;

			if (exp != null) {
				var mult : Float = exp;
				if (e.ctrlKey) mult *= 10.0;
				if (e.shiftKey) mult /= 10.0;

				newValue = value * hxd.Math.exp(delta * mult);
			} else {
				var mult : Float = step;
				if (mult == null)
					mult = isInt ? 1 : 0.01;

				if (step == null && !isInt) {
					if (min != null && max != null) {
						var currentStep = hxd.Math.floor(hxd.Math.log10(hxd.Math.abs(max-min)));
						mult = hxd.Math.pow(10.0, currentStep-2);
					}
				}
				if (e.ctrlKey) mult *= 10.0;
				if (e.shiftKey) mult /= 10.0;
				newValue = value + delta * mult;
			}

			if (wrap && min != null && max !=null) {
				var size = max - min;
				newValue = ((newValue - min + size) % size) + min;
			} else {
				if (min != null)
					newValue = hxd.Math.max(newValue, min);
				if (max != null)
					newValue = hxd.Math.min(newValue, max);
			}

			slideTo(cast newValue, true);
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
		slider = new hrt.ui.HuiSlider();
		slider.slider.onChange = () -> {
			value = slider.slider.value;
			broadcastValueChange(true);
		}
		slider.slider.minValue = -10;
		slider.slider.maxValue = 10;
		return slider;
		#end
	}

	function slideTo(newValue: T, isTemporary: Bool) {
		var group = Std.downcast(parent, SliderGroup);
		if (group != null && group.isLocked) {
			var changeDelta = newValue / value;

			var sliders : Array<Widget<Dynamic>> = [];
			for (sibling in parent.children) {
				var siblingSlider = Std.downcast(sibling, Slider);
				if (siblingSlider == null)
					continue;

				if (Math.isFinite(changeDelta)) {
					siblingSlider.value = cast (siblingSlider.value:Float) * changeDelta;
				} else {
					siblingSlider.value = cast newValue;
				}
				sliders.push(siblingSlider);
			}

			root.broadcastValuesChange(sliders, isTemporary);
		}
		else {
			value = newValue;
			if (isInt) {
				value = cast hxd.Math.round(cast value);
			}
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

	override function syncValueUI() {
		if (slider == null)
			return;
		#if js
		slider.value = Std.string(hxd.Math.round(value * 100) / 100);
		#else
		slider.slider.value = value;
		#end

		if (showRange && min != null && max != null) {
			var alpha = hxd.Math.clamp((value - min) / (max - min)) * 100;
			#if js
			slider.style.background = 'linear-gradient(to right, #3185ce ${alpha}%, #222222 ${alpha}%)';
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