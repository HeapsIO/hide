package hide.kit;

#if domkit

typedef SelectEntry = {value:Dynamic, label:String};

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

	public function setEntries(entries: EntriesOrStrings) {
		this.entries = entries;
		value = null;
		syncValueUI();
	}

	#if js
	var select: NativeElement;
	var text: NativeElement;
	var dropdown = null;
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
		text = js.Browser.document.createSpanElement();
		select.appendChild(text);

		select.onclick = (e: js.html.MouseEvent) -> {
			var selectEntries: Array<hide.comp.ContextMenu.MenuItem> = [for (i => entry in entries) {label: entry.label, click: valueChanged.bind(entry)}];
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
		#end
		return null;
	}

	override function syncValueUI() {
		#if js
		if (text == null)
			return;
		var label = "--- Select ---";
		for (entry in entries) {
			if (entry.value == value) {
				label = entry.label;
				break;
			}
		}
		text.innerText = label;
		#end
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}

	function stringToValue(obj: String) : Dynamic {
		for (entry in entries) {
			if (haxe.Json.stringify(entry.value) == obj) {
				return entry.value;
			}
		}
		return null;
	}
}

#end