package hrt.ui;



#if hui

class HuiErrorDisplay extends HuiElement {
	static var SRC =
		<hui-error-display>
			<hui-text id="error-title"/>
			<hui-text id="error-exception"/>
			<hui-virtual-list id="stack-trace"/>
			<hui-button id="copy-button"><hui-text("Copy Error")/></hui-button>
		</hui-error-display>

	var prevError: String = null;

	public function new(?parent) {
		super(parent);
		initComponent();

		stackTrace.generateItem = generateItem;
		copyButton.onClick = (e) -> {
			hxd.System.setClipboardText(prevError);
			hide.Ide.showInfo("Error copied to clipboard");
		}
	}

	function generateItem(e: haxe.CallStack.StackItem) {
		var elem = new HuiElement();
		var b = new StringBuf();
		@:privateAccess haxe.CallStack.itemToString(b, e);
		var text = new HuiText(b.toString(), elem);
		return elem;
	}

	public function setError(title: String, exception: haxe.Exception) {
		var fmtError = hide.Ide.formatError(title, exception);
		if (fmtError == prevError)
			return;
		prevError = fmtError;

		this.visible = true;
		stackTrace.setItems(haxe.CallStack.exceptionStack(true));
		errorTitle.text = title;
		errorException.text = 'Exception : $exception';
	}

	public function clearError() {
		this.visible = false;
		stackTrace.setItems([]);
		errorTitle.text = "";
		errorException.text = "";
		prevError = null;
	}
}

#end