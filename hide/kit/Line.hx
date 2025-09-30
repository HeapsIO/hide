package hide.kit;

class Line extends Element {
	public var label(default, set): String;

	function set_label(v: String) : String {
		label = v;
		#if js
		if (v == null) {
			labelElement?.remove();
			return label;
		}

		if (labelElement == null) {
			labelElement = js.Browser.document.createElement("kit-label");
			native.prepend(labelElement);
		}

		labelElement.innerHTML = label;

		#else
		throw "implement";
		#end
		return label;
	}

	public var labelElement: NativeElement;

	override function makeNative():NativeElement {
		#if js
		return js.Browser.document.createElement("kit-line");
		#else
		throw "aaa";
		#end
	}
}