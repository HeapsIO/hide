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
			gradientBox.value = value ?? hrt.impl.Gradient.getDefaultGradientData();
		#end
	}

	function getDefaultFallback() : hrt.impl.Gradient.GradientData {
		return hrt.impl.Gradient.getDefaultGradientData();
	}

	function stringToValue(str:String) : Null<hrt.impl.Gradient.GradientData> {
		var parsedData = try {
			haxe.Json.parse(str);
		} catch(e) {
			return null;
		}
		return hrt.impl.TextureType.Utils.getGradientData(parsedData);
	}
}

#end