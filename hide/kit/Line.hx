package hide.kit;

class Line extends Element {
	public var label(default, set): String;
	public var multiline: Bool = false;
	public var fullWidth: Bool = false;

	function set_label(v: String) : String {
		label = v;
		refreshLabel();
		return label;
	}

	#if js
	public var labelElement: NativeElement;
	#else
	public var labelContainer: hidehl.ui.Element;
	public var labelText: hidehl.ui.FmtText;
	#end

	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-line");
		if (multiline) {
			native.classList.add("multiline");
		}
		refreshLabel();
		#else
		native = new hidehl.ui.Element();
		native.dom.addClass("line");
		refreshLabel();
		#end
	}

	function refreshLabel() {
		if (native == null)
			return;
		#if js
		if (label == null && fullWidth) {
			labelElement?.remove();
			return;
		}

		if (labelElement == null) {
			labelElement = js.Browser.document.createElement("kit-label");
			labelElement.classList.add("first");
			native.prepend(labelElement);
		}

		labelElement.innerHTML = label ?? "";
		#else
		if (label == null) {
			labelContainer?.remove();
			return;
		}

		if (labelContainer == null) {
			labelContainer = new hidehl.ui.Element(native);
			labelContainer.dom.addClass("label");
			labelContainer.dom.addClass("first");

			labelText = new hidehl.ui.FmtText(labelContainer);
		}

		labelText.text = label;
		#end
	}
}