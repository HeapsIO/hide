package hide.kit;

#if domkit

class Checkbox extends Widget<Bool> {
	#if js
	var checkbox : js.html.InputElement;
	#else
	var checkbox : NativeElement;
	#end

	function makeInput() : NativeElement {
		#if js
		checkbox = js.Browser.document.createInputElement();
		checkbox.type = "checkbox";

		checkbox.addEventListener("input", () -> {
			value = checkbox.checked;
			broadcastValueChange(false);
		});

		return checkbox;
		#else
		return new hrt.ui.HuiFmtText("checkbox");
		#end
	}

	override function syncValueUI() {
		#if js
		if (checkbox != null)
			checkbox.checked = value;
		#end
	}

	function getDefaultFallback() : Bool {
		return false;
	}

	function stringToValue(obj: String) : Null<Bool> {
		if (obj.toLowerCase() == "true")
			return true;
		if (obj.toLowerCase() == "false")
			return false;
		return null;
	}
}

#end