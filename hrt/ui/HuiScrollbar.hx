package hrt.ui;

#if hui
class HuiScrollbar extends HuiElement {
	public function new(?parent) {
		super(parent);
		initComponent();

		onAfterReflow = () -> {
			x = parentElement.calculatedWidth - this.minWidth - 2;
		};
	}
}

#end