package hide.kit;

/**
	Base class for all hide elements that manipulate a Value, like sliders, inputs etc...
**/
abstract class Widget<ValueType> extends Element {
	public var label(default, set): String;
	@:isVar public var value(get, set): ValueType;

	function set_label(v: String) : String {
		label = v;
		#if js
		if (labelElement != null)
			labelElement.innerHTML = label;
		#else
		if (labelElement != null)
			labelElement.text = label;
		#end
		return label;
	}

	var input: NativeElement;

	#if js
	var labelElement: NativeElement;
	#else
	var labelElement: hidehl.ui.HuiFmtText;
	#end

	function get_value() return value;
	function set_value(v:ValueType) {
		value = v;
		if (input != null)
			syncValueUI();
		return value;
	}

	override function makeSelf():Void {
		var parentLine = Std.downcast(parent, Line);

		#if js
		if (parentLine == null) {
			native = js.Browser.document.createElement("kit-line");
		} else {
			native = js.Browser.document.createElement("kit-div");
		}

		labelElement = js.Browser.document.createElement("kit-label");
		if (parentLine == null) {
			labelElement.classList.add("first");
		}
		labelElement.innerHTML = label;

		native.appendChild(labelElement);

		input = makeInput();
		native.appendChild(input);

		#else
		if (parentLine == null) {
			native = new hidehl.ui.HuiElement();
			native.dom.addClass("line");
		} else {
			native = new hidehl.ui.HuiElement();
			native.dom.addClass("widget");
		}

		var labelContainer = new hidehl.ui.HuiElement(native);
		labelContainer.dom.addClass("label");

		labelElement = new hidehl.ui.HuiFmtText(labelContainer);
		labelElement.text = label;

		if (parentLine == null || (parent.children[0] == this && parentLine.label == null)) {
			labelContainer.dom.addClass("first");
		}

		input = makeInput();
		native.addChild(input);
		#end
		syncValueUI();
	}

	abstract function makeInput() : NativeElement;

	public dynamic function onValueChange(temporaryEdit: Bool) : Void {

	}

	/**
		Call this internally when the user interact with the widget to change the value
	**/
	function broadcastValueChange(temporaryEdit) : Void {
		root.broadcastValueChange(this, temporaryEdit);
	}

	function syncValueUI() {

	}
}