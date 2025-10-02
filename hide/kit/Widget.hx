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
		throw "implement";
		#end
		return label;
	}

	var input: NativeElement;
	var labelElement: NativeElement;

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
		if (parentLine == null || (parent.children[0] == this && parentLine.label == null)) {
			labelElement.classList.add("first");
		}
		labelElement.innerHTML = label;

		native.appendChild(labelElement);

		input = makeInput();
		native.appendChild(input);

		syncValueUI();
		#else
		throw "aaa";
		#end
	}

	abstract function makeInput() : NativeElement;

	public dynamic function onValueChange(temporaryEdit: Bool) : Void {

	}

	/**
		Call this internaly when the user interract with the widget to change the value
	**/
	function broadcastValueChange(temporaryEdit) : Void {
		properties.broadcastValueChange(this, temporaryEdit);
	}

	// public function bindField(fieldName: String, object: Dynamic, onChange: (propName: String) -> Void) {
	// 	var previousValue = value;
	// 	var editing = false;
	// 	onValueChange = (temporaryEdit) -> {
	// 		if (!editing) {
	// 			previousValue = value;
	// 			editing = true;
	// 		}

	// 		Reflect.setProperty(fieldName, object);
	// 		if (onChange != null) {
	// 			onChange(fieldName);
	// 		}

	// 		if (!temporaryEdit) {
	// 			editorContext.properties.undo.change()
	// 		}
	// 	}
	// }

	function syncValueUI() {

	}
}