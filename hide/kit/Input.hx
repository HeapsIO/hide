package hide.kit;

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

		input.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (e.key == "Enter") {
				e.preventDefault();
				e.stopPropagation();
				input.blur();
			} else if (e.key == "Escape") {
				e.preventDefault();
				e.stopPropagation();
				input.value = value;
				input.blur();
			}
		});

		syncPlaceholder();

		return input;
		#end
	}

	function syncPlaceholder() {
		if (input != null) {
			input.setAttribute("placeholder", placeholder);
		}
	}
}