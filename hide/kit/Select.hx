package hide.kit;

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
	public var entries(default, null) : Array<SelectEntry>;

	#if js
	var select: NativeElement;
	var text: NativeElement;
	var dropdown = null;
	#end

	public function new(parent: Element, id: String, entries: EntriesOrStrings) {
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

		var selectEntries: Array<hide.comp.ContextMenu.MenuItem> = [for (i => entry in entries) {label: entry.label, click: valueChanged.bind(entry)}];
		select.onclick = (e: js.html.MouseEvent) -> {
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
