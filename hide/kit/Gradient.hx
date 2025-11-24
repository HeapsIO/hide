package hide.kit;

#if domkit

class Gradient extends Widget<hrt.impl.Gradient.GradientData> {
	#if js
	var gradientBox: hide.comp.GradientEditor.GradientBox;
	#end

	function makeInput() : NativeElement {
		#if js
		gradientBox = new hide.comp.GradientEditor.GradientBox();
		gradientBox.onChange = (isTemp) -> {
			value = gradientBox.value;
			broadcastValueChange(isTemp);
		}

		return gradientBox.element[0];
		#end
		return null;
	}

	override function syncValueUI() {
		#if js
		if (gradientBox != null)
			gradientBox.value = value ?? getDefaultFallback();
		#end
	}

	function getDefaultFallback() : hrt.impl.Gradient.GradientData {
		return haxe.Json.parse(haxe.Json.stringify(hrt.impl.Gradient.getDefaultGradientData()));
	}

	function stringToValue(str:String) : Null<hrt.impl.Gradient.GradientData> {
		var parsedData = try {
			haxe.Json.parse(str);
		} catch(e) {
			return null;
		}
		return hrt.impl.TextureType.Utils.getGradientData(parsedData);
	}

	override function valueEqual(a: hrt.impl.Gradient.GradientData, b: hrt.impl.Gradient.GradientData) : Bool {
		return hrt.prefab.Diff.diff(a, b) == Skip;
	}
}

#end