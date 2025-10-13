package hide.kit;

class Color extends Widget<Int> {

	var alpha : Bool = false;

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
}