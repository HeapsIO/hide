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

	inline function getParentFlow() : h2d.Flow {
		return cast parent;
	}

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		enableInteractive = true;

		interactive.onOver = onOver;
		interactive.onPush = onPush;

		if (getParentFlow() == null)
			throw "Splitter parent must be a flow";
	}

	public function onOver(e: hxd.Event) {
		interactive.cursor = switch(direction) {
			case Horizontal:
				ResizeWE;
			case Vertical:
				ResizeNS;
			default:
				throw "unsupported";
		}
	}

	public function onPush(e: hxd.Event) {
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
							resize(getScene().mouseX - originalOffset);
						case Vertical:
							resize(getScene().mouseY - originalOffset);
						default:
							throw "unsupported";
					}
				}
			});
		}
	}

	public function resize(newAbsPos: Float) {
		var parentFlow = getParentFlow();
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

		var props = parentFlow.getProperties(before);
		switch(direction) {
			case Horizontal:
				if (props.autoSizeWidth != null) {
					toChange = after;
					other = before;
					parentPadding = parentFlow.paddingRight;
				} else {
					toChange = before;
					other = after;
					parentPadding = parentFlow.paddingLeft;
				}
				thisSize = calculatedWidth;
				parentSize = parentFlow.calculatedWidth;
				parentOrigin = parentFlow.absX;
				parentGap = parentFlow.horizontalSpacing;
				otherMinSize = other.minWidth;
			case Vertical:
				if (props.autoSizeHeight != null) {
					toChange = after;
					parentPadding = parentFlow.paddingBottom;
				} else {
					toChange = before;
					parentPadding = parentFlow.paddingTop;
				}
				thisSize = calculatedHeight;
				parentSize = parentFlow.calculatedHeight;
				parentOrigin = parentFlow.absY;
				parentGap = parentFlow.verticalSpacing;
			default:
				throw "unsupported";
		}


		var size = (newAbsPos - parentOrigin);
		if (toChange == after)
			size = parentSize - size - thisSize;
		size -= parentPadding + parentGap;

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