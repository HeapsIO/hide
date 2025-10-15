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
	var select: hide.comp.Select;
	#end

	public function new(parent: Element, id: String, entries: EntriesOrStrings) {
		super(parent, id);
		this.entries = entries;
	}

	function makeInput() : NativeElement {
		#if js
		var selectEntries: Array<hide.comp.Dropdown.Choice> = [for (i => entry in entries) {id: '$i', text: entry.label, searchText: entry.label}];
		select = new hide.comp.Select(null, null, selectEntries, true);
		select.onChange = (newId) -> {
			value = newId != null ? entries[Std.parseInt(newId)]?.value : null;
			broadcastValueChange(false);
		}
		return select.element[0];
		#end
		return null;
	}

	override function syncValueUI() {
		#if js
		var index = -1;
		for (i => entry in entries) {
			if (entry.value == value) {
				index = i;
			}
		}
		select.value = index == -1 ? null : '$index';
		#end
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}
}
