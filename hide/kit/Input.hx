package hide.kit;

#if domkit

class Input extends Widget<String> {
	public var placeholder(default, set) : String;
	function set_placeholder(v) {
		placeholder = v;
		syncPlaceholder();
		return placeholder;
	}

	function makeInput():NativeElement {
		#if js
		var input = js.Browser.document.createInputElement();
		this.input = input;

		input.addEventListener("input", (e: js.html.InputEvent) -> {
			value = input.value;
			broadcastValueChange(true);
		});

		input.addEventListener("blur", (e: js.html.FocusEvent) -> {
			value = input.value;
			broadcastValueChange(false);
		});

		var inputSave = null;
		input.addEventListener("focus", (e: js.html.InputEvent) -> {
			inputSave = input.value;
		});

		input.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.key == "Enter") {
				e.preventDefault();
				e.stopPropagation();
				input.blur();
			} else if (e.key == "Escape") {
				e.preventDefault();
				e.stopPropagation();
				if (inputSave != null)
					input.value = inputSave;
				inputSave = null;
				input.blur();
			}
		});

		syncPlaceholder();

		return input;
		#else
		throw "Implement";
		#end
	}

	function syncPlaceholder() {
		#if js
		if (input != null && placeholder != null) {
			input.setAttribute("placeholder", placeholder);
		}
		#end
	}

	override function syncValueUI() {
		#if js
		if (input != null)
			(cast input: js.html.InputElement).value = value ?? "";
		#end
	}

	function getDefaultFallback() : String {
		return null;
	}

	function stringToValue(str: String) : String {
		return str;
	}
}

#end