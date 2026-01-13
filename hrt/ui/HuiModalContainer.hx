package hrt.ui;

#if hui

/**
	An invisible element that take the whole screen,
	used to catch mouse events for popups and other related widgets
**/
class HuiModalContainer extends HuiElement {
	static var SRC =
		<hui-modal-container>
		</hui-modal-container>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}

#end