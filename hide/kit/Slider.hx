package hide.kit;

class Slider extends Widget<Float> {
	#if js
	var slider: js.html.InputElement;
	#else
	var slider: hidehl.ui.HuiSlider;
	#end

	public var min(default, set) : Null<Float> = null;
	public var max(default, set) : Null<Float> = null;
	public var step : Float = 1.0;
	public var wrap: Bool = false;
	var showRange: Bool = false;

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

			var mult = step;
			if (e.ctrlKey) mult *= 10.0;
			if (e.shiftKey) mult /= 10.0;
			value += e.movementX * mult;

			if (wrap && min != null && max !=null) {
				var size = max - min;
				value = ((value - min + size) % size) + min;
			} else {
				if (min != null)
					value = hxd.Math.max(value, min);
				if (max != null)
					value = hxd.Math.min(value, max);
			}


			broadcastValueChange(true);
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
				broadcastValueChange(false);
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
				@:bypassAccessor value = newValue;

				broadcastValueChange(true);
			}
		});

		slider.addEventListener("blur", (e: js.html.FocusEvent) -> {
			var newValue = Std.parseFloat(slider.value);
			value = newValue ?? value;
			broadcastValueChange(false);
		});

		return container;
		#else
		slider = new hidehl.ui.HuiSlider();
		slider.slider.onChange = () -> {
			value = slider.slider.value;
			broadcastValueChange(true);
		}
		slider.slider.minValue = -10;
		slider.slider.maxValue = 10;
		return slider;
		#end
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
}