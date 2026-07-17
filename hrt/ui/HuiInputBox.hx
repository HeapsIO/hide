package hrt.ui;

#if hui
class HuiInputBox extends HuiElement {
	static var SRC =
		<hui-input-box>
			<hui-text-input public id="textInput"/>
			<hui-element id="icon"/>
		</hui-input-box>

	public var text(get, set) : String;
	public var disabled : Bool = false;
	var canceled = false;

	public var preventDefault = false;

	/**
		Allow to intercept inputs before they reach the internal TextInput.
		set preventDefault to true to stop the normal behavior of the InputBox
	**/
	public dynamic function onBeforeKeyDown(e: hxd.Event) {

	}

	function get_text() : String {
		return textInput.text;
	}

	function set_text(v: String) : String {
		return textInput.text = v;
	}

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		textInput.text = "";

		onAfterReflow = afterReflow;

		textInput.onKeyDown = onKeyDownInternal;
		textInput.onTextInput = onTextInputInternal;
		textInput.onKeyUp = onKeyUpInternal;
		textInput.onFocus = onFocusInternal;
		textInput.onFocusLost = onFocusLostInternal;
		textInput.onChange = onChangeInternal;
	}

	public function focus() {
		textInput.focus();
	}

	function afterReflow() {
		textInput.maxWidth = innerWidth;
	}

	override function onKeyDownInternal(e:hxd.Event) {
		if(HuiBase.get(this).checkCommand(e, this)) {
			textInput.preventDefault = true;
			return;
		}

		preventDefault = false;
		onBeforeKeyDown(e);
		if (preventDefault) {
			textInput.preventDefault = true;
			return;
		}

		if (e.keyCode == hxd.Key.ENTER) {
			textInput.blur();
			e.propagate = true;
			return;
		}
		if (e.keyCode == hxd.Key.ESCAPE) {
			canceled = true;
			textInput.blur();
			e.propagate = true;
			return;
		}
		super.onKeyDownInternal(e);
	}

	override function onFocusInternal(e: hxd.Event) {
		canceled = false;
		super.onFocusInternal(e);
	}

	public dynamic function onChange(isTempChange: Bool) {

	}

	override function onFocusLostInternal(e: hxd.Event) {
		super.onFocusLostInternal(e);
		if (!canceled && getScene() != null) {
			onChange(false);
		}
	}

	function onChangeInternal() {
		onChange(true);
	}
}
#end