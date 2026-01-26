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
	}
}

#end
