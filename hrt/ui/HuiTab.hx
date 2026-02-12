package hrt.ui;

#if hui

class HuiTab extends HuiElement {
	static var SRC =
		<hui-tab>
			<hui-text("") id="title"/>
			<hui-element id="close-button"/>
		</hui-tab>

	var targetElement: HuiElement;

	public function new(targetElement: HuiElement, ?parent) {
		super(parent);
		initComponent();

		this.targetElement = targetElement;
		onClose = null;

		closeButton.onClick = (e) -> {
			if (onClose != null)
				onClose();
		}
	}

	public var onClose(default, set) : Void -> Void;

	function set_onClose(v) {
		onClose = v;
		closeButton.dom.toggleClass("hidden", onClose == null);
		return onClose;
	}

}

#end
