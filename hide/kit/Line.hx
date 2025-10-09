package hide.kit;

class Line extends Element {
	public var label(default, set): String;
	public var multiline: Bool = false;

	function set_label(v: String) : String {
		label = v;
		refreshLabel();
		return label;
	}

	public var labelElement: NativeElement;

	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-line");
		if (multiline) {
			native.classList.add("multiline");
		}
		refreshLabel();
		#else
		throw "aaa";
		#end
	}

	function refreshLabel() {
		if (native == null)
			return;
		#if js
		if (label == null) {
			labelElement?.remove();
			return;
		}

		if (labelElement == null) {
			labelElement = js.Browser.document.createElement("kit-label");
			labelElement.classList.add("first");
			native.prepend(labelElement);
		}

		labelElement.innerHTML = label;
		#else
		throw "implement";
		#end
	}
}