package hide.kit;

class Slider extends Input<Float> {
	var slider: js.html.InputElement;

	function makeInput() : WrappedElement {
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
			onValueChange(true);
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
				onValueChange(false);
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
				onValueChange(true);
			}
		});

		slider.addEventListener("blur", (e: js.html.FocusEvent) -> {
			var newValue = Std.parseInt(slider.value);
			value = newValue ?? value;
			onValueChange(false);
		});

		return container;
		#else
		throw "implement";
		#end
	}

	override function syncValue() {
		slider?.value = Std.string(hxd.Math.round(value * 100) / 100);
	}
}