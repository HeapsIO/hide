package hrt.ui;

class HuiScrollbar extends HuiElement {
	public function new(?parent) {
		super(parent);
		initComponent();

		onAfterReflow = () -> {
			x = parentElement.calculatedWidth - this.minWidth - 2;
		};
	}
}