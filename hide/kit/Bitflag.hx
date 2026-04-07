package hide.kit;

#if domkit

class Bitflag extends Widget<Int> {
	#if js
	var checkbox : js.html.InputElement;
	#elseif hui
	var checkbox : hrt.ui.HuiCheckbox;
	#end

	var bit: Int;
	public function new(parent: Element, id: String, bit: Int) {
		super(parent, id);
		this.bit = bit;
	}

	function makeInput() : NativeElement {
		#if js
		checkbox = js.Browser.document.createInputElement();
		checkbox.type = "checkbox";

		checkbox.addEventListener("input", () -> {
			setBit(checkbox.checked);
			broadcastValueChange(false);
			root.editor.rebuildInspector(); // stupid hack to sync all the other bitflags that share the same field
		});

		return checkbox;
		#elseif hui
		var cb = new hrt.ui.HuiCheckbox();
		cb.value = getBit();
		cb.onValueChanged = () -> {
			setBit(cb.value);
			broadcastValueChange(false);
			root.editor.rebuildInspector(); // stupid hack to sync all the other bitflags that share the same field
		};
		checkbox = cb;
		return checkbox;
		#else
		return null;
		#end
	}

	function setBit(on: Bool) {
		if (on) {
			value = value | (1 << bit);
		} else {
			value = value & ~(1 << bit);
		}
	}

	function getBit() : Bool {
		return value & (1 << bit) != 0;
	}

	override function customIndeterminate():Bool {
		return true;
	}

	override function syncValueUI() {
		#if js
		if (checkbox != null) {
			checkbox.indeterminate = isIndeterminate();
			checkbox.checked = getBit();
		}
		#elseif hui
		checkbox.value = getBit();
		#end
	}

	function getDefaultFallback() : Int {
		return 0;
	}

	function stringToValue(obj: String) : Null<Int> {
		return Std.parseInt(obj);
	}
}

#end