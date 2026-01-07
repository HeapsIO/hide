package hide.kit;

#if domkit

/**
	Base class for all hide elements that manipulate a Value, like sliders, inputs etc...
**/
abstract class Widget<ValueType> extends Element {
	public var label(default, set): String;
	@:isVar public var value(get, set): ValueType;
	public var defaultValue: ValueType;

	public var labelColor(default, set): KitColor = White;

	var fieldName: String;

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

	function set_labelColor(v: KitColor) : KitColor {
		labelColor = v;
		syncKitColor();
		return labelColor;
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
		if (input != null) {
			if (!syncQueued) {
				syncQueued = true;
				// delay the sync value so all side effects are accounted for (useful for isIndeterminate())
				haxe.Timer.delay(() -> {syncQueued = false; syncValueUI();}, 0);
			}
		}
		return value;
	}
	var syncQueued = false;

	function syncKitColor() {
		Element.setNativeColor(labelElement, labelColor);
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

		if (!customIndeterminate() && isIndeterminate()) {
			makeIndeterminateWidget();
		}
		else {
			input = makeInput();
			setupPropLine(labelElement, input);
			syncValueUI();
		}

		syncKitColor();
	}

	function makeIndeterminateWidget() : Void {
		#if js

		labelElement = js.Browser.document.createElement("kit-label");
		labelElement.innerHTML = label;

		var indeterminate = js.Browser.document.createElement("kit-div");
		var label = js.Browser.document.createElement("kit-label");
		label.innerHTML = "Multiple Values";
		indeterminate.appendChild(label);

		var reset = js.Browser.document.createElement("kit-button");
		reset.innerHTML = "Reset";
		indeterminate.appendChild(reset);

		var paste = js.Browser.document.createElement("kit-button");
		paste.innerHTML = "Paste";
		indeterminate.appendChild(paste);

		reset.onclick = (e) -> {
			value = defaultValue ?? getDefaultFallback();
			broadcastValueChange(false);
			root.editor.rebuildInspector();
		}

		paste.onclick = (e) -> {
			pasteFromClipboard();
			root.editor.rebuildInspector();
		}

		setupPropLine(labelElement, indeterminate);
		#end
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
		parent?.change(changeBehaviorInternal.bind(temporaryEdit), temporaryEdit);
	}

	/** Internal function passed to change() **/
	function changeBehaviorInternal(isTemporaryEdit: Bool) {
		onFieldChange(isTemporaryEdit);
		onValueChange(isTemporaryEdit);
		@:privateAccess root.prefab?.updateInstance(fieldName);

		var idPath = getIdPath();
		for (childProperties in root.editedPrefabsProperties) {
			var childElement = childProperties.getElementByPath(idPath);
			var childInput = Std.downcast(childElement, Type.getClass(this));

			if (childInput != null) {
				childInput.value = haxe.Json.parse(haxe.Json.stringify(value));
				childInput.onFieldChange(isTemporaryEdit);
				childInput.onValueChange(isTemporaryEdit);
				@:privateAccess childProperties.prefab?.updateInstance(fieldName);
			}
		}
	}

	/** Returns true if the values between the currently edited prefabs differs **/
	function isIndeterminate() : Bool {
		if (root.editedPrefabsProperties.length == 0) {
			return false;
		}
		var id = getIdPath();
		for (editors in root.editedPrefabsProperties) {
			var other : Widget<ValueType> = cast editors.getElementByPath(id);
			if (other != null) {
				if (!valueEqual(value, other.value))
					return true;
			}
		}
		return false;
	}

	/**
		Called when `value` has changed to update the UI accordingly
	**/
	function syncValueUI() {

	}

	/**
		Override this to return true if your prefab handles the indeterminate state in another manner
		than replacing the widget with the indeterminate widget
	**/
	function customIndeterminate() : Bool {
		return false;
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

	function valueEqual(a: ValueType, b: ValueType) : Bool {
		return a == b;
	}
}

#end