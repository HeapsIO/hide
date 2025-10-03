package hide.kit;

class Checkbox extends Widget<Bool> {
	var checkbox : js.html.InputElement;

	function makeInput() : NativeElement {
		#if js
		checkbox = js.Browser.document.createInputElement();
		checkbox.type = "checkbox";

		checkbox.addEventListener("input", () -> {
			value = checkbox.checked;
			trace(value);
			broadcastValueChange(false);
		});

		return checkbox;
		#end
	}

	override function syncValueUI() {
		#if js
		if (checkbox != null)
			checkbox.checked = value;
		#end
	}
}