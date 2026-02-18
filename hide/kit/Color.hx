package hide.kit;

#if domkit

class Color extends Widget<Dynamic> {
	public var alpha : Bool = false;

	/**
		If the input is an h3d.Vector
	**/
	public var vec : Bool = false;

	/**
		If the input is an Array<Float>
	**/
	public var arr : Bool = false;

	#if js
	var colorBox : hide.comp.ColorPicker.ColorBox;
	#end

	function makeInput():NativeElement {
		#if js
		colorBox = new hide.comp.ColorPicker.ColorBox(null, null, true, alpha);
		colorBox.onChange = (isTemp) -> {
			if (arr) {
				var vec = h3d.Vector4.fromColor(colorBox.value);
				value = alpha ? [vec.x, vec.y, vec.z, vec.w] : [vec.x, vec.y, vec.z];
			}
			else if (vec) {
				(value:h3d.Vector4).setColor(colorBox.value);
			} else {
				value = colorBox.value;
			}
			broadcastValueChange(isTemp);
		}
		return colorBox.element[0];
		#else
		return null;
		#end
	}

	override function syncValueUI() {
		#if js
		if (colorBox != null) {
			if (arr) {
				var v = h3d.Vector4.fromArray(value);
				colorBox.value = v.toColor();
			}
			else if (vec) {
				colorBox.value = (value:h3d.Vector4).toColor();
			} else {
				colorBox.value = value;
			}
		}
		#end
	}

	function getDefaultFallback() : Dynamic {
		if (vec) {
			(value:h3d.Vector4).setColor(0);
			return value;
		}
		return 0;
	}

	override function pasteSelf(obj: Dynamic) {
		if (obj.value != null) {
			// if (vec) {
			// 	if (Std.isOfType(obj.value, Int)) {
			// 		(value:h3d.Vector4).setColor(obj.value);
			// 	}
			// 	else {
			// 		(value:h3d.Vector4).load(value);
			// 	}
			// } else {
			// 	if (Std.isOfType(obj.value, Int)) {
			// 		value = obj.value;
			// 	} else {
			// 		value =
			// 	}
			// }
			value = obj.value;
			broadcastValueChange(true);
		}
	}

	function stringToValue(str: String) : Null<Dynamic> {
		return hrt.impl.ColorSpace.Color.intFromString(str, alpha);
	}
}

#end