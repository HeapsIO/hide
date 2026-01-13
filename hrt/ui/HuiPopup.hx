package hrt.ui;

#if hui

class HuiPopup extends HuiElement {
	static var SRC =
		<hui-popup>
		</hui-popup>

	public function close() {
		remove();
	}
}

#end