package hide.comp;


typedef Options = {
	?hasDropdown: Bool,
}

/**
	Dropdown that uses a ContextMenu for it's dropdown element
**/
class Button extends hide.comp.Component {
	public var label(default, set) : String;

	var labelElem : hide.Element;
	function set_label(newLabel: String) : String {
		label = newLabel;
		labelElem.text(label);
		return label;
	}

	public function new(parent: hide.Element = null, ?label: String, ?options: Options) {
		options ??= {};
		super(parent, new Element("<button-2></button-2>"));
		labelElem = new Element("<value></value>").appendTo(element);

		this.label = label;

		if (options.hasDropdown) {
			new Element('<div class="ico ico-chevron-down"></div>').appendTo(element);
		}

		element.click((e) -> onClick());
	}

	public dynamic function onClick() {

	}
}