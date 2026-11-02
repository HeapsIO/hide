package hide.html.comp;

import hide.html.WebComponent;

/**
	Button showing its `icon` (path from `res`) and `label` attributes, then its children, in a row. Classes : `small-square`, `medium-square`, `quiet`, `dropdown` (adds an arrow after the children), `small-dropdown` (narrow arrow button next to another one).
	Setting `oncheck(event, checked)` makes it a toggle : a click flips the `checked` attribute.
**/
@:keep
class Button extends WebComponent {
	public var oncheck : (e : js.html.Event, checked : Bool) -> Void;

	@:attr public var icon : Null<String>;
	@:attr public var label : Null<String>;

	var iconElement : Icon;
	var labelElement : js.html.SpanElement;

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

	function set_icon(old : Null<String>, v : Null<String>) {
		if (old == v)
			return;

		if (v == null) {
			iconElement?.remove();
			iconElement = null;
			return;
		}
		if (iconElement == null) {
			iconElement = Icon.create();
			shadowRoot.prepend(iconElement);
		}
		iconElement.setAttribute("icon", v);
	}

	function set_label(old : Null<String>, v : Null<String>) {
		if (old == v)
			return;

		if (v == null) {
			labelElement?.remove();
			labelElement = null;
			return;
		}
		if (labelElement == null) {
			labelElement = js.Browser.document.createSpanElement();
			labelElement.className = "label";
			if (iconElement != null)
				iconElement.after(labelElement);
			else
				shadowRoot.prepend(labelElement);
		}
		labelElement.textContent = v;
	}

	static var _ = register(Button, "hide-button");
}
