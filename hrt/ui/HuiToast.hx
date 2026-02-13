package hrt.ui;


#if hui

enum ToastKind {
	Info;
	Warning;
	Error;
}

class HuiToast extends HuiElement {
	static var SRC =
		<hui-toast>
			<hui-element id="icon-container">
				<hui-element id="icon"/>
			</hui-element>
			<hui-element id="text-container">
				<hui-text("") id="text"/>
			</hui-element>
		</hui-toast>

	public function new(message: String, kind: ToastKind, ?parent) {
		super(parent);
		initComponent();

		text.text = message;

		switch (kind) {
			case Info:
				dom.addClass("info");
			case Warning:
				dom.addClass("warning");
			case Error:
				dom.addClass("error");
		}

		onClick = (e) -> {
			remove();
		}
	}
}

#end