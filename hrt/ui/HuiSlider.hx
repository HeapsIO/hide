package hrt.ui;

#if hui
class HuiSlider extends HuiElement {
	static var SRC = <hui-slider>
			<hui-element id="fillBar"/>
			<hui-text id="valueText"/>
			<hui-text-input id="inputText"/>
	</hui-slider>

	@:p public var value(default, set) : Float = 0.0;
	@:p public var defaultValue : Float = 0.0;
	@:p public var min : Null<Float> = null;
	@:p public var max : Null<Float> = null;
	@:p public var wrap : Bool = false;
	@:p public var step : Null<Float> = null;
	@:p public var decimals : Null<Int> = 3;

	var textChanged = false;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		inputText.visible = false;
		valueText.visible = true;

		inputText.onChange = () -> {
			textChanged = true;
		}

		inputText.onFocusLost = (e: hxd.Event) -> {
			inputText.visible = false;
			valueText.visible = true;
			if (textChanged) {
				var newValue = Std.parseFloat(inputText.text);
				if (hxd.Math.isFinite(newValue)) {
					value = newValue;
					onValueChanged(false);
				}
			}
		};

		inputText.onFocus = (e: hxd.Event) -> {
			textChanged = false;
			inputText.visible = true;
			valueText.visible = false;
			inputText.text = Std.string(value);
			haxe.Timer.delay(() -> inputText.focus(), 0);
		};

		var moved = false;
		var startX = -1;
		var startY = -1;
		this.onPush = (e : hxd.Event) -> {
			if (inputText.visible)
				return;
			startX = hxd.Window.getInstance().mouseX;
			var accumulator= 0.0;
			startY = hxd.Window.getInstance().mouseY;
			var startValue = value;
			var started = false;
			hxd.Window.getInstance().mouseMode = Relative((event: hxd.Event) -> {
				var scale = hxd.Key.isDown(hxd.Key.SHIFT) ? 0.1 : 1.0;

				accumulator += event.relX / getScene().viewportScaleX;

				if (!started) {
					// add a small margin before actually dragging the slider
					if (hxd.Math.abs(accumulator) > 3 && !started) {
						started = true;
						accumulator = 0;
					}
				} else {
					var steps = hxd.Math.round(accumulator);

					if (hxd.Math.abs(steps) > 0) {
						if (min != null && max != null) {
							value = startValue + (steps * scale) * (max - min) / 1000.0;
						} else {
							value = startValue + (steps * scale) * (step ?? 0.01);
						}

						if (wrap) {
							if (min != null && max != null) {
								var size = max - min;
								value = ((value - min + size) % size) + min;
							}
						} else {
							if (min != null) value = hxd.Math.max(min, value);
							if (max != null) value = hxd.Math.min(max, value);
						}
						moved = true;
						onValueChanged(true);
					}
				}
			}, true);
		};

		this.onRelease = (e : hxd.Event) -> {
			if (inputText.visible)
				return;
			if (startX >= 0 && startY >= 0) {
				hxd.Window.getInstance().mouseMode = Absolute;
				hxd.Window.getInstance().setCursorPos(startX, startY);
				if (!moved) {
					inputText.visible = true;
					valueText.visible = false;
					haxe.Timer.delay(() -> inputText.focus(), 0);
				}
				else {
					moved = false;
					onValueChanged(false);
				}
			}
			startX = -1;
			startY = -1;
		}
	}

	override function onAfterReflow() {
		refreshSlider();
	}

	function refreshSlider() {
		fillBar.minWidth = max == null ? 0 : hxd.Math.round(hxd.Math.clamp(this.innerWidth * ((value - min) / (max - min)), 0, this.innerWidth));
		valueText.text = getDisplayString();
		this.tip = Std.string(value);
	}

	/**
		Returns the value rounded to `decimals` decimals. If the rounded value differs from the actual value,
		all the decimals up to `decimals` are displayed followed by "..." to indicate that the actual value has more digits.
	**/
	public function getDisplayString() : String {
		if (decimals == null || !Math.isFinite(value))
			return Std.string(value);

		var dec = hxd.Math.imin(decimals, 15);
		var p = Math.pow(10, dec);
		var scaled = Math.fround(Math.abs(value) * p);

		// Relative tolerance so float64 arithmetic noise (e.g. 0.1 + 0.2 = 0.30000000000000004) isn't reported as extra digits.
		// Float64 epsilon is ~2.2e-16, so 1e-12 leaves room for accumulated error from repeated operations
		var exact = Math.abs(Math.abs(value) - scaled / p) <= Math.abs(value) * 1e-12;

		var intPart = Math.ffloor(scaled / p);
		// Kept as a Float : Std.int would overflow with more than 9 decimals
		var fracDigits = dec > 0 ? Std.string(scaled - intPart * p) : "";
		while (fracDigits.length < dec)
			fracDigits = "0" + fracDigits;

		if (exact) {
			var end = fracDigits.length;
			while (end > 0 && fracDigits.charCodeAt(end - 1) == "0".code)
				end--;
			fracDigits = fracDigits.substr(0, end);
		}

		var str = (value < 0 ? "-" : "") + Std.string(intPart);
		if (fracDigits.length > 0)
			str += "." + fracDigits;
		if (!exact)
			str += "...";
		return str;
	}

	function set_value(v : Float) {
		value = v;
		refreshSlider();
		return value;
	}

	public dynamic function onValueChanged(tempChanges : Bool) {}
}
#end
