package hide.kit;

#if domkit

typedef SelectEntry = {
	value:Dynamic,
	label:String,
	?equalsNull: Bool, // if true, this value will be displayed if the input value is null
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

	public function setEntries(entries: EntriesOrStrings) {
		this.entries = entries;
		value = null;
		syncValueUI();
	}

	#if js
	var select: hide.html.comp.Select;
	#elseif hui
	var select : hrt.ui.HuiSelect;
	#end

	public function new(parent: Element, id: String, entries: EntriesOrStrings = null) {
		super(parent, id);
		this.entries = entries;
	}

	function makeInput() : NativeElement {
		#if js
		select = hide.html.comp.Select.create();
		select.onValueChanged = () -> {
			value = select.value;
			syncValueUI();
			broadcastValueChange(false);
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
		if (select == null)
			return;
		select.items = [for (entry in entries) {label: entry.label, value: entry.value}];
		var label = "--- Select ---";
		for (entry in entries) {
			if ((entry.value == value) || (entry.equalsNull && value == null) ) {
				label = entry.label;
				break;
			}
		}
		select.label = label;
		#elseif hui
		if (select == null)
			return;
		select.items = [for (i => entry in entries) { label: entry.label, value: entry.value }];
		for (entry in entries) {
			if ((entry.value == value) || (entry.equalsNull && value == null) ) {
				select.value = entry.value;
				break;
			}
		}
		#end
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}

	override function resetSelf() {
		value = defaultValue ?? (entries?.length > 0 ? entries[0].value : null);
		broadcastValueChange(true);
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