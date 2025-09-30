package hide.kit;

abstract class Input<ValueType> extends Element {
	public var label(default, set): String;
	@:isVar public var value(get, set): ValueType;

	function set_label(v: String) : String {
		label = v;
		#if js
		labelElement.innerHTML = label;
		#else
		throw "implement";
		#end
		return label;
	}

	var input: WrappedElement;
	var labelElement: WrappedElement;

	function get_value() return value;
	function set_value(v:ValueType) {
		value = v;
		syncValue();
		return value;
	}

	override function makeWrap():WrappedElement {
		var parentLine = Std.downcast(parent, Line);

		#if js
		var container : WrappedElement;
		if (parentLine == null) {
			container = js.Browser.document.createElement("kit-line");
		} else {
			container = js.Browser.document.createElement("kit-div");
		}

		labelElement = js.Browser.document.createElement("kit-label");
		container.appendChild(labelElement);

		input = makeInput();
		container.appendChild(input);

		return container;
		#else
		throw "aaa";
		#end
	}

	abstract function makeInput() : WrappedElement;

	public dynamic function onValueChange(temporaryEdit: Bool) : Void {

	}

	function syncValue() {

	}
}