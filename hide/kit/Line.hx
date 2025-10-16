package hide.kit;

class Line extends Element {
	public var label: String;
	public var multiline: Bool = false;
	public var full: Bool = false;

	#if js
	public var labelElement: NativeElement;
	#else
	public var labelContainer: hrt.ui.HuiElement;
	public var labelText: hrt.ui.HuiFmtText;
	#end

	override function makeSelf():Void {
		#if js
		if (!full) {
			labelElement = js.Browser.document.createElement("kit-label");
			labelElement.innerText = label ?? "";
		}

		setupPropLine(labelElement, null);

		if (multiline) {
			native.classList.add("multiline");
		}

		#else
		native = new hrt.ui.HuiElement();
		native.dom.addClass("line");
		//refreshLabel();
		#end
	}

	// function refreshLabel() {
	// 	if (native == null)
	// 		return;
	// 	#if js
	// 	if (full) {
	// 		labelElement?.remove();
	// 		return;
	// 	}

	// 	if (labelElement == null) {
	// 		labelElement = js.Browser.document.createElement("kit-label");
	// 		labelElement.classList.add("first");
	// 		native.prepend(labelElement);
	// 	}

	// 	labelElement.innerHTML = label ?? "";
	// 	#else
	// 	if (label == null) {
	// 		labelContainer?.remove();
	// 		return;
	// 	}

	// 	if (labelContainer == null) {
	// 		labelContainer = new hrt.ui.HuiElement(native);
	// 		labelContainer.dom.addClass("label");
	// 		labelContainer.dom.addClass("first");

	// 		labelText = new hrt.ui.HuiFmtText(labelContainer);
	// 	}

	// 	labelText.text = label;
	// 	#end
	// }
}