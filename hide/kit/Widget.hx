package hide.kit;

/**
	Base class for all hide elements that manipulate a Value, like sliders, inputs etc...
**/
abstract class Widget<ValueType> extends Element {
	public var label(default, set): String;
	@:isVar public var value(get, set): ValueType;
	public var defaultValue: ValueType;

	function new(parent: Element, id: String) {
		super(parent, id);
		defaultValue = getDefaultFallback();
	}

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
		labelElement = js.Browser.document.createElement("kit-label");
		labelElement.innerHTML = label;
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

		input = makeInput();
		native.addChild(input);
		#end

		input = makeInput();
		setupPropLine(labelElement, input);
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

	override function reset() {
		value = defaultValue;
		root.broadcastValueChange(this, true);
		super.reset();
	}

	abstract function getDefaultFallback() : ValueType;
}