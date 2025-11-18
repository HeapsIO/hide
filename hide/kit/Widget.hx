package hide.kit;

#if domkit

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
	var labelElement: hrt.ui.HuiFmtText;
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
			native = new hrt.ui.HuiElement();
			native.dom.addClass("line");
		} else {
			native = new hrt.ui.HuiElement();
			native.dom.addClass("widget");
		}

		var labelContainer = new hrt.ui.HuiElement(native);
		labelContainer.dom.addClass("label");

		labelElement = new hrt.ui.HuiFmtText(labelContainer);
		labelElement.text = label;

		input = makeInput();
		native.addChild(input);
		#end

		input = makeInput();
		setupPropLine(labelElement, input);
		syncValueUI();
	}

	/**
		Create the underlying input element
	**/
	abstract function makeInput() : NativeElement;

	/**
		Called when value has been changed by the user
	**/
	public dynamic function onValueChange(temporaryEdit: Bool) : Void {

	}

	/**
		Internal version of onValueChange for field editing
	**/
	dynamic function onFieldChange(temporaryEdit: Bool) : Void {

	}

	/**
		Call this internally when the user interact with the widget to indicate to the Inspector that the value has changed
	**/
	function broadcastValueChange(temporaryEdit: Bool) : Void {
		parent?.propagateChange(Value([this], temporaryEdit));
	}

	/**
		Called when `value` has changed to update the UI accordingly
	**/
	function syncValueUI() {

	}

	override function resetSelf() {
		value = defaultValue;
		broadcastValueChange(true);
	}

	override function copySelf(target: Dynamic) {
		target.value = value;
	}

	override function pasteSelf(obj: Dynamic) {
		if (obj.value != null) {
			value = obj.value;
			broadcastValueChange(true);
		}
	}

	override function pasteSelfString(str: String) {
		var parsedValue = stringToValue(str);
		if (parsedValue != null) {
			value = parsedValue;
			broadcastValueChange(true);
		}
	}

	override function canCopy():Bool {
		return true;
	}

	override function canPaste():Bool {
		return true;
	}

	override function canReset():Bool {
		return true;
	}

	/** Returns null if the value can't be parsed**/
	abstract function stringToValue(str: String) : Null<ValueType>;

	abstract function getDefaultFallback() : ValueType;
}

#end