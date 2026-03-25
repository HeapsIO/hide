package hrt.ui;



#if hui

enum ConfirmButton {
	Save;
	DontSave;
	Cancel;
	Close;
	Ok;
}

typedef ConfirmButtons = haxe.EnumFlags<ConfirmButton>;

class HuiConfirmPopup extends HuiPopup {
	static var SRC =
		<hui-confirm-popup>
			<hui-text("") id="text-message"/>
			<hui-element id="buttons-container">
			</hui-element>
		</hui-confirm-popup>

	var onCompletion: ConfirmButton -> Void;

	public function new(message: String, ?buttons: hrt.ui.HuiConfirmPopup.ConfirmButtons, onCompletion: ConfirmButton -> Void, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.onCompletion = onCompletion;

		if (buttons == null)
			buttons = ConfirmButton.Ok | ConfirmButton.Cancel;
		textMessage.text = message;

		var names = haxe.EnumTools.getConstructors(ConfirmButton);
		for (i => name in names) {
			var e = haxe.EnumTools.createByIndex(ConfirmButton, i);
			if (buttons.has(e)) {
				var button = new HuiButton(buttonsContainer);
				new HuiText(getDisplayString(e) ?? name, button);
				button.onClick = (_) -> complete(e);
			}
		}
	}

	function getDisplayString(button: ConfirmButton) : Null<String> {
		return switch(button) {
			case DontSave: "Don't Save";
			default:
				null;
		}
	}

	public function complete(button: ConfirmButton) {
		close();
		onCompletion(button);
	}
}


#end