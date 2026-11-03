package hide.html.comp;

import hide.html.WebComponent;

/**
	Lays out its children (buttons, groups) in a row.
**/
@:keep
class Toolbar extends WebComponent {
	public function new() {
		super();
		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];
		root.append(js.Browser.document.createSlotElement());
	}

	static var _ = register(Toolbar, "hide-toolbar");
}
