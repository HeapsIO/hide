package hide.html.comp;

import hide.html.WebComponent;

/**
	Button showing its `icon` (path from `res`) and `label` attributes, then its children, in a row. Classes : `small-square`, `medium-square`, `quiet`, `dropdown` (adds an arrow after the children), `small-dropdown` (narrow arrow button next to another one).
	Setting `oncheck(event, checked)` makes it a toggle : a click flips the `checked` attribute.
**/
@:keep
class Button extends WebComponent {
	static var observedAttributes = ["icon", "label"];

	public var oncheck : (e : js.html.Event, checked : Bool) -> Void;

	var icon : Icon;
	var label : js.html.SpanElement;

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

	override public function attributeChangedCallback(name : String, oldValue : Null<String>, newValue : Null<String>) {
		switch (name) {
			case "icon":
				if (newValue == null) {
					icon?.remove();
					icon = null;
					return;
				}
				if (icon == null) {
					icon = Icon.create();
					shadowRoot.prepend(icon);
				}
				icon.setAttribute("icon", newValue);

			case "label":
				if (newValue == null) {
					label?.remove();
					label = null;
					return;
				}
				if (label == null) {
					label = js.Browser.document.createSpanElement();
					label.className = "label";
					if (icon != null)
						icon.after(label);
					else
						shadowRoot.prepend(label);
				}
				label.textContent = newValue;
		}
	}

	static var _ = register(Button, "hide-button");
}
