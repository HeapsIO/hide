package hide.comp;

typedef SearchRanges = Array<Int>;
class FancySearch extends hide.comp.Component {
	var open = false;
	var input : js.html.InputElement;


	public override function new(parent: Element = null, target: Element = null) {
		var el = new hide.Element('
			<fancy-search>
				<input type="text" class="search-field">
				<fancy-icon class="search-icon fi-search"></fancy-icon>
			</fancy-search>
		');
		if (target != null) {
			target.replaceWith(el);
		}
		super(parent, el);

		input = cast element.get(0).querySelector(".search-field");

		input.oninput = (e) -> {
			onSearch(e.target.value, false);
		}

		input.onchange = (e) -> {
			onSearch(e.target.value, true);
		}
	}

	public function getValue() {
		return input.value;
	}

	public dynamic function onSearch(search: String, enter: Bool) : Void {};

	public function hasFocus() : Bool {
		return js.Browser.document.activeElement ==  input;
	}

	public function blur() : Void {
		input.blur();
	}

	public function focus() : Void {
		input.focus();
	}

	public static function computeSearchRanges(haystack: String, needle: String) : SearchRanges {
		if (needle == null || needle == "")
			return [];
		var pos = haystack.toLowerCase().indexOf(needle);
		if (pos < 0)
			return null;
		return [pos, pos + needle.length];
	}

	public static function splitSearchRanges(string: String, ranges: SearchRanges, openToken: String = "<span class='search-hl'>", closeToken: String = "</span>") : String {
		var lastPos = 0;
		var finalName = "";
		for (index in 0...(ranges.length>>1)) {
			var len = ranges[index+1] - ranges[index];
			if (len > 0) {
				var first = string.substr(lastPos, ranges[index]);
				var match = string.substr(ranges[index], len);
				finalName += first + openToken + match + closeToken;
			}
			lastPos = ranges[index+1];
		}
		finalName += string.substr(lastPos);
		return finalName;
	}
}