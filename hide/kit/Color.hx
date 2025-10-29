package hide.kit;

class Color extends Widget<Int> {
	public var alpha : Bool = false;

	#if js
	var colorBox : hide.comp.ColorPicker.ColorBox;
	#end

	function makeInput():NativeElement {
		#if js
		colorBox = new hide.comp.ColorPicker.ColorBox(null, null, true, alpha);
		colorBox.onChange = (isTemp) -> {
			value = colorBox.value;
			broadcastValueChange(isTemp);
		}
		return colorBox.element[0];
		#end
		throw "implement";
	}

	override function syncValueUI() {
		#if js
		if (colorBox != null) {
			colorBox.value = value;
		}
		#end
	}

	function getDefaultFallback() : Int {
		return 0;
	}

	function stringToValue(str: String) : Null<Int> {
		return hrt.impl.ColorSpace.Color.intFromString(str, alpha);
	}
}