package hide.html.comp;

import hide.html.WebComponent;

/**
	Button showing its children (`.ico`, `.label`) in a row. Classes : `small-square`, `medium-square`, `quiet`, `small-dropdown` (narrow arrow button next to another one).
	Setting `oncheck(event, checked)` makes it a toggle : a click flips the `checked` attribute.
**/
@:keep
class Button extends WebComponent {
	public var oncheck : (e : js.html.Event, checked : Bool) -> Void;

	public function new() {
		super();
		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];
		root.append(js.Browser.document.createSlotElement());

		addEventListener("click", (e) -> {
			if (oncheck != null)
				oncheck(e, toggleAttribute("checked"));
		});
	}

	static var _ = register(Button, "hide-button");
}
