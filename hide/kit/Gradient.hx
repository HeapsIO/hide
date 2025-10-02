package hide.kit;

class Gradient extends Widget<hrt.impl.Gradient.GradientData> {
	var gradientBox: hide.comp.GradientEditor.GradientBox;

	function makeInput() : NativeElement {
		gradientBox = new hide.comp.GradientEditor.GradientBox();
		gradientBox.onChange = (isTemp) -> {
			value = gradientBox.value;
			broadcastValueChange(isTemp);
		}

		return gradientBox.element[0];
	}

	override function syncValueUI() {
		#if js
		if (gradientBox != null)
			gradientBox.value = value ?? hrt.impl.Gradient.getDefaultGradientData();
		#end
	}
}