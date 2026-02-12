package hrt.ui;

#if hui

enum Direction {
	Horizontal;
	Vertical;
}

enum AnchorTo {
	Start;
	End;
}

class HuiSplitContainer extends HuiElement {
	static var SRC =
		<hui-split-container>
			<hui-splitter id="splitter"/>
		</hui-split-container>

	@:p var direction(default, set) : Direction = Horizontal;
	@:p var firstMinSize(default, set): Int = 0;
	@:p var firstMaxSize(default, set): Int = 100_000;
	@:p var secondMinSize(default, set): Int = 0;
	@:p var secondMaxSize(default, set): Int = 100_000;

	/**
		Whenever the splitterPos value is relative to the start or end position of this container
	**/
	@:p var anchorTo: AnchorTo = Start;

	function set_firstMinSize(v) {needReflow = true; return firstMinSize = v;};
	function set_firstMaxSize(v) {needReflow = true; return firstMaxSize = v;};
	function set_secondMinSize(v) {needReflow = true; return secondMinSize = v;};
	function set_secondMaxSize(v) {needReflow = true; return secondMaxSize = v;};

	var splitterPos : Int = 200;

	function set_direction(v: Direction) {
		direction = v;
		splitter.dom.toggleClass("vertical", direction == Vertical);
		splitter.dom.toggleClass("horizontal",  direction == Horizontal);
		return v;
	}

	public function new(?parent) {
		super(parent);
		initComponent();
		splitter.onResize = onSplitterMove;
		onAfterReflow = updateLayout;
		direction = direction;
	}


	override function onLoadState() {
		splitterPos = getDisplayState("splitterPos", splitterPos);
		needReflow = true;
	}

	function updateLayout() {
		var childElement = childElements;

		// Ensure splitter is always at the end (so it's over other elements)
		if (childElements.indexOf(splitter) != childElements.length - 1) {
			splitter.remove();
			addChild(splitter);
		}

		childElement = this.childElements;


		var paddingStart = 0;
		var paddingEnd = 0;
		var spacing = 0;
		var splitterSize = 0;
		var size = 0;
		switch (direction) {
			case Horizontal:
				for (element in childElements) {
					element.minHeight = element.maxHeight = innerHeight;
					element.y = paddingTop;
				}

				paddingStart = paddingLeft;
				paddingEnd = paddingRight;
				spacing = horizontalSpacing;
				splitterSize = splitter.minWidth;
				size = Std.int(calculatedWidth);
			case Vertical:
				for (element in childElements) {
					element.minWidth = element.maxWidth = innerWidth;
					element.x = paddingLeft;
				}

				paddingStart = paddingTop;
				paddingEnd = paddingBottom;
				spacing = verticalSpacing;
				splitterSize = splitter.minHeight;
				size = Std.int(calculatedHeight);
		}

		var firstPos = 0;
		var firstSize = 0;
		var secondPos = 0;
		var secondSize = 0;

		var localSplitterPos = switch (anchorTo) {
			case Start:
				splitterPos;
			case End:
				size - splitterPos;
		}

		// try to fit constraints for min/max sizes
		for (maxConstraint in 0...4) {
			firstPos = paddingStart;
			firstSize = localSplitterPos - firstPos - spacing;
			secondPos = localSplitterPos + splitterSize + spacing;
			secondSize = size - secondPos - paddingEnd;

			if (firstSize < firstMinSize) {
				localSplitterPos += firstMinSize - firstSize;
				continue;
			}

			if (firstSize > firstMaxSize) {
				localSplitterPos += firstMaxSize - firstSize;
				continue;
			}

			if (secondSize < secondMinSize) {
				localSplitterPos -= secondMinSize - secondSize;
				continue;
			}

			if (secondSize > secondMaxSize) {
				localSplitterPos -= secondMaxSize - secondSize;
				continue;
			}
		}

		switch (direction) {
			case Horizontal:
				childElement[0].x = firstPos;
				childElement[0].setWidth(firstSize);
				childElement[1].x = secondPos;
				childElement[1].setWidth(secondSize);
				splitter.x = localSplitterPos;
			case Vertical:
				childElement[0].y = firstPos;
				childElement[0].setHeight(firstSize);
				childElement[1].y = secondPos;
				childElement[1].setHeight(secondSize);
				splitter.y = localSplitterPos;
		}

		splitterPos = switch(anchorTo) {
			case Start:
				localSplitterPos;
			case End:
				size - localSplitterPos;
		}

		saveDisplayState("splitterPos", splitterPos);
	}

	function onSplitterMove(newPos: Float) {
		splitterPos = Std.int(newPos);
		switch (anchorTo) {
			case Start:
			case End:
				var size = switch (direction) {
					case Horizontal:
						calculatedWidth;
					case Vertical:
						calculatedHeight;
					}
				splitterPos = Std.int(size) - splitterPos;
		}
		needReflow = true;
	}
}

#end