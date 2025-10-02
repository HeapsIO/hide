package hide.kit;

class Slider extends Input<Float> {
	var slider: js.html.InputElement;

	public var min(default, set) : Null<Float> = null;
	public var max(default, set) : Null<Float> = null;

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

			var mult = 1.0;
			if (e.ctrlKey) mult *= 10.0;
			if (e.shiftKey) mult /= 10.0;
			value += e.movementX * mult;
			if (min != null)
				value = hxd.Math.max(value, min);
			if (max != null)
				value = hxd.Math.min(value, max);

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

		slider.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.key == "Enter") {
				e.preventDefault();
				e.stopPropagation();
				slider.blur();
			}
		});

		slider.addEventListener("input", (e: js.html.InputEvent) -> {
			var newValue = Std.parseInt(slider.value);
			if (newValue != null) {
				@:bypassAccessor value = newValue;

				broadcastValueChange(true);
			}
		});

		slider.addEventListener("blur", (e: js.html.FocusEvent) -> {
			var newValue = Std.parseInt(slider.value);
			value = newValue ?? value;
			broadcastValueChange(false);
		});

		return container;
		#else
		throw "implement";
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
		slider.value = Std.string(hxd.Math.round(value * 100) / 100);

		if (min != null && max != null) {
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