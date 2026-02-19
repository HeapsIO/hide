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
	@:p public var step : Null<Float> = null;
	@:p public var decimals : Null<Int> = null;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		inputText.visible = false;
		valueText.visible = true;
		inputText.onFocusLost = (e: hxd.Event) -> {
			inputText.visible = false;
			valueText.visible = true;
			value = Std.parseFloat(inputText.text);
			onValueChanged(false);
		};

		var moved = false;
		this.onPush = (e : hxd.Event) -> {
			hxd.Window.getInstance().mouseMode = Relative((event: hxd.Event) -> {
				var scale = hxd.Key.isDown(hxd.Key.SHIFT) ? 0.1 : 1.0;

				if (min != null && max != null) {
					value += (event.relX * scale) * (max - min) / 400.0;
				} else {
					value += (event.relX * scale) * (step ?? 1);
				}

				if (min != null) value = hxd.Math.max(min, value);
				if (max != null) value = hxd.Math.min(max, value);
				moved = true;
				onValueChanged(true);
			}, true);
		};

		this.onRelease = (e : hxd.Event) -> {
			hxd.Window.getInstance().mouseMode = Absolute;
			if (!moved) {
				inputText.visible = true;
				valueText.visible = false;
				inputText.text = valueText.text;
				haxe.Timer.delay(() -> inputText.focus(), 0);
			}
			else {
				moved = false;
				onValueChanged(false);
			}
		}
	}

	override function onAfterReflow() {
		refreshSlider();
	}

	function refreshSlider() {
		fillBar.minWidth = max == null ? 0 : hxd.Math.round(hxd.Math.clamp(this.innerWidth * (value / max), 0, this.innerWidth));
		valueText.text = '${decimals == null ? value : hxd.Math.round(value * Math.pow(10, decimals)) / Math.pow(10, decimals)}';
	}

	function set_value(v : Float) {
		value = v;
		refreshSlider();
		return value;
	}

	public dynamic function onValueChanged(tempChanges : Bool) {}
}
#end
