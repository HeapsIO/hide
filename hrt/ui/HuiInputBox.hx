package hrt.ui;

#if hui
class HuiInputBox extends HuiElement {
	static var SRC =
		<hui-input-box>
			<hui-text-input public id="textInput"/>
			<hui-element id="icon"/>
		</hui-input-box>

	public var text(get, set) : String;

	function get_text() : String {
		return textInput.text;
	}

	function set_text(v: String) : String {
		return textInput.text = v;
	}

	function new(?parent: h2d.Object) {
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

	function afterReflow() {
		textInput.maxWidth = innerWidth;
	}

	public dynamic function onChange() {

	}

	function onChangeInternal() {
		onChange();
	}
}
#end