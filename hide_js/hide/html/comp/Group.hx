package hide.html.comp;

import hide.html.WebComponent;

/**
	Joins its children in a row, without gap nor inner rounded corners.
**/
@:keep
class Group extends WebComponent {
	public function new() {
		super();
		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];
		root.append(js.Browser.document.createSlotElement());
	}

	static var _ = register(Group, "hide-group");
}
