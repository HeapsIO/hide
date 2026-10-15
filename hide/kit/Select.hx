package hide.kit;

#if domkit

typedef SelectEntry = {
	value:Dynamic,
	label:String,
	?equalsNull: Bool, // if true, this value will be displayed if the input value is null
	/** If set, this entry is a sub menu of these entries, its own value is not selectable **/
	?children: Array<SelectEntry>,
	/** HTML shown before the label, in the dropdown and in the select (a thumbnail) **/
	?preview: String,
	/** A separator line in the dropdown, not selectable **/
	?separator: Bool,
};

abstract EntriesOrStrings(Array<SelectEntry>) from Array<SelectEntry> to Array<SelectEntry> {
	inline function new(i:Array<SelectEntry>) {
		this = i;
	}

	@:from
	static public function fromStringArray(strings:Array<String>) {
		return new EntriesOrStrings([for (string in strings) {value: string, label: string}]);
	}
}

class Select extends Widget<Dynamic> {
	/**
		List of entries to be displayed in the select list. If field is set and the field is an enum or an abstract enum,
		and if entries is left to null, then the entries will be automatically generated from the given enum (see `hide.kit.Macros.tryAutoSelect()`)
	**/
	public var entries(default, null) : Array<SelectEntry>;

	/** Only the caret is shown, the value in the tooltip **/
	public var caretOnly = false;

	/** Shown when the value is none of the entries **/
	public var placeholder = "--- Select ---";

	public function setEntries(entries: EntriesOrStrings) {
		this.entries = entries;
		value = null;
		syncValueUI();
	}

	#if js
	var select: NativeElement;
	var text: NativeElement;
	var dropdown = null;
	#elseif hui
	var select : hrt.ui.HuiSelect;
	#end

	public function new(parent: Element, id: String, entries: EntriesOrStrings = null) {
		super(parent, id);
		this.entries = entries;
	}

	function makeInput() : NativeElement {
		#if js
		function valueChanged(newValue: SelectEntry) {
			value = newValue.value;
			broadcastValueChange(false);
		}

		select = js.Browser.document.createElement("kit-select");
		select.toggleClass("kit-caret-only", caretOnly);
		text = js.Browser.document.createSpanElement();
		select.addChild(text);

		// with sub menus or without the value shown, the dropdown marks the current entry
		var mark = false;
		function menu(entries: Array<SelectEntry>) : Array<hrt.ui.HuiMenu.MenuItem> {
			return [for (entry in entries)
				if (entry.separator == true)
					{ isSeparator: true }
				else if (entry.children != null)
					{ label: entry.label, menu: menu(entry.children), icon: mark && Lambda.exists(flatten(entry.children), e -> e.value == value) ? "check" : null }
				else
					{ label: (entry.preview ?? "") + entry.label, click: valueChanged.bind(entry), icon: mark && entry.value == value ? "check" : null }
			];
		}

		select.get().onclick = (e: js.html.MouseEvent) -> {
			mark = caretOnly || Lambda.exists(entries, e -> e.children != null);
			var selectEntries = menu(entries);
			if (dropdown == null) {
				dropdown = hide.comp.ContextMenu.createDropdown(select, selectEntries);
				dropdown.onClose = () -> {
					dropdown = null;
				}
			} else {
				dropdown.close();
			}
		}

		return select;
		#elseif hui
		var s = new hrt.ui.HuiSelect();
		s.onValueChanged = () -> {
			value = s.value;
			broadcastValueChange(false);
		}
		select = s;
		syncValueUI();
		return s;
		#end
		return null;
	}

	override function syncValueUI() {
		#if js
		if (text == null)
			return;
		var label = placeholder, preview = null;
		for (entry in flatten(entries)) {
			if ((entry.value == value) || (entry.equalsNull && value == null) ) {
				label = entry.label;
				preview = entry.preview;
				break;
			}
		}
		text.get().innerText = label;
		if (preview != null)
			text.get().insertAdjacentHTML("afterbegin", preview);
		if (caretOnly)
			select.get().title = label;
		#elseif hui
		if (select == null)
			return;
		select.items = [for (entry in flatten(entries)) { label: entry.label, value: entry.value }];
		for (entry in flatten(entries)) {
			if ((entry.value == value) || (entry.equalsNull && value == null) ) {
				select.value = entry.value;
				break;
			}
		}
		#end
	}

	/** The selectable entries, the ones of the sub menus included **/
	static function flatten(entries: Array<SelectEntry>) : Array<SelectEntry> {
		var out = [];
		for (e in entries ?? [])
			if (e.children != null)
				out = out.concat(flatten(e.children));
			else if (e.separator != true)
				out.push(e);
		return out;
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}

	function stringToValue(obj: String) : Dynamic {
		for (entry in flatten(entries)) {
			if (haxe.Json.stringify(entry.value) == obj) {
				return entry.value;
			}
		}
		return null;
	}
}

#end