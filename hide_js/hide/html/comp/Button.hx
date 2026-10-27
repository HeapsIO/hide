package hide.html.comp;

import hide.html.WebComponent;

/**
	Button showing its children (`.ico`, `.label`) in a row. Classes : `small-square`, `medium-square`, `quiet`, `small-dropdown` (narrow arrow button next to another one).
**/
@:keep
class Button extends WebComponent {
	public function new() {
		super();
		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];
		root.append(js.Browser.document.createSlotElement());
	}

	static var _ = register(Button, "hide-button");
}
