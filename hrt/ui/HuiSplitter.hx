package hrt.ui;

#if hui

class HuiSplitter extends HuiElement {
	static var SRC =
		<hui-splitter>
		</hui-splitter>

	var direction(get, never): h2d.Flow.FlowLayout;

	function get_direction() {
		return dom.hasClass("vertical") ? Vertical : Horizontal;
	}

	function new(?parent: h2d.Object) {
		super(parent);
		initComponent();


		onOver = over;
		onPush = push;
	}

	function over(e: hxd.Event) {
		interactive.cursor = switch(direction) {
			case Horizontal:
				ResizeWE;
			case Vertical:
				ResizeNS;
			default:
				throw "unsupported";
		}
	}

	function push(e: hxd.Event) {
		if (e.button == 0) {
			var originalOffset = switch(direction) {
				case Horizontal:
					getScene().mouseX - absX;
				case Vertical:
					getScene().mouseY - absY;
				default:
					throw "unsupported";
			}
			getScene().startCapture((e: hxd.Event) -> {
				if (!hxd.Key.isDown(hxd.Key.MOUSE_LEFT)) {
					getScene().stopCapture();
				} else {
					switch(direction) {
						case Horizontal:
							onResize(getScene().mouseX - originalOffset - parent.absX);
						case Vertical:
							onResize(getScene().mouseY - originalOffset - parent.absY);
						default:
							throw "unsupported";
					}
				}
			});
		}
	}

	dynamic public function onResize(newAbsPos: Float) {

	}
}

#end