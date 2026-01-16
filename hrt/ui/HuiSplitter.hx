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

	public function resize(newAbsPos: Float) {
		var parentFlow = parentElement;
		var before : h2d.Flow = cast parent.children[parent.children.length - 3];
		var after : h2d.Flow = cast parent.children[parent.children.length - 1];

		var toChange : h2d.Flow;
		var other : h2d.Flow;
		var parentSize: Float = 0;
		var parentPadding: Float = 0;
		var thisSize: Float = 0;
		var parentGap : Float = 0;
		var parentOrigin: Float = 0;
		var splitterMargin: Float = 0;
		var otherMinSize: Float = 0;
		var otherPadding: Float = 0;

		var props = parentFlow.getProperties(before);
		switch(direction) {
			case Horizontal:
				if (props.autoSizeWidth != null) {
					toChange = after;
					other = before;
					parentPadding = parentFlow.paddingRight;
					otherPadding = parentFlow.paddingLeft;

				} else {
					toChange = before;
					other = after;
					parentPadding = parentFlow.paddingLeft;
					otherPadding = parentFlow.paddingRight;
				}
				thisSize = calculatedWidth;
				parentSize = parentFlow.calculatedWidth;
				parentOrigin = parentFlow.absX;
				parentGap = parentFlow.horizontalSpacing;
				otherMinSize = other.minWidth ?? 4; //need to find out why where these 4 pixels are
			case Vertical:
				if (props.autoSizeHeight != null) {
					toChange = after;
					other = before;
					parentPadding = parentFlow.paddingBottom;
				} else {
					toChange = before;
					other = after;
					parentPadding = parentFlow.paddingTop;
				}
				thisSize = calculatedHeight;
				parentSize = parentFlow.calculatedHeight;
				parentOrigin = parentFlow.absY;
				parentGap = parentFlow.verticalSpacing;
				otherMinSize = other.minHeight ?? 4;
			default:
				throw "unsupported";
		}


		var size = (newAbsPos - parentOrigin);
		if (toChange == after)
			size = parentSize - size - thisSize;
		size -= parentPadding + parentGap;
		var remaining = (parentSize - (otherMinSize + otherPadding + parentGap)) - size;
		trace(remaining);
		if (remaining < 0) {
			size += remaining;
		}

		switch(direction) {
			case Horizontal:
				toChange.maxWidth = toChange.minWidth = Std.int(size);
			case Vertical:
				toChange.maxHeight = toChange.minHeight = Std.int(size);
			default:
		}
	}
}

#end