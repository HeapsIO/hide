package hide.html.comp;

import hide.html.WebComponent;
import hrt.ui.HuiSelect.HuiSelectOption;

/**
	Dropdown showing its `label` attribute. A click (or Enter / Space) opens a menu with `items`.
	Picking an item sets `value` to its value, then calls `onValueChanged`.
**/
@:keep
class Select extends WebComponent {
	@:attr public var label : Null<String>;

	/**
		Setting it changes `label` to the label of the matching item of `items`.
	**/
	public var value(default, set) : Dynamic;

	/**
		Setting it refreshes `label` from `value`.
	**/
	public var items(default, set) : Array<HuiSelectOption>;

	var labelElement : js.html.SpanElement;
	var dropdown : hide.comp.ContextMenu;
	var internals : hide.html.ElementInternals;

	public dynamic function onValueChanged() {
	}

	public function new() {
		super();
		// The setter would add an attribute, forbidden in the constructor of a custom element
		@:bypassAccessor items = [];

		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];

		labelElement = js.Browser.document.createSpanElement();
		labelElement.className = "label";
		root.append(labelElement);

		internals = attachInternals();
		internals.role = "combobox";
		internals.ariaExpanded = "false";

		addEventListener("click", toggle);
		addEventListener("keydown", (e : js.html.KeyboardEvent) -> {
			if (e.key == "Enter" || e.key == " ") {
				e.preventDefault();
				toggle();
			}
		});
	}

	override function connectedCallback() {
		if (!hasAttribute("tabindex"))
			tabIndex = 0;
	}

	function toggle() {
		if (dropdown != null) {
			dropdown.close();
			return;
		}

		var menu : Array<hrt.ui.HuiMenu.MenuItem> = [for (item in items) {
			label: item.label,
			click: () -> {
				value = item.value;
				onValueChanged();
			},
		}];
		dropdown = hide.comp.ContextMenu.createDropdown(this, menu);
		internals.ariaExpanded = "true";
		dropdown.onClose = () -> {
			dropdown = null;
			internals.ariaExpanded = "false";
		}
	}

	function set_label(old : Null<String>, v : Null<String>) {
		labelElement.textContent = v ?? "";
	}

	function set_value(v : Dynamic) : Dynamic {
		value = v;
		if (v == null) {
			label = "-- None --";
			return v;
		}

		var item = Lambda.find(items, i -> i.value == v);
		label = item != null ? item.label : '$v (missing)';
		return v;
	}

	function set_items(v : Array<HuiSelectOption>) : Array<HuiSelectOption> {
		items = v;
		value = value;
		return v;
	}

	static var _ = register(Select, "hide-select");
}
