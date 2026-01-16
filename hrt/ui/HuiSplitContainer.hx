package hrt.ui;

#if hui

enum Direction {
	Horizontal;
	Vertical;
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
	}

	function updateLayout() {
		var childElement = childElements;
		var paddingStart = 0;
		var paddingEnd = 0;
		var spacing = 0;
		var splitterSize = 0;
		var size = 0;
		trace(paddingTop);
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

		// try to fit constraints for min/max sizes
		for (maxConstraint in 0...4) {
			firstPos = paddingStart;
			firstSize = splitterPos - firstPos - spacing;
			secondPos = splitterPos + splitterSize + spacing;
			secondSize = size - secondPos - paddingEnd;

			if (firstSize < firstMinSize) {
				splitterPos += firstMinSize - firstSize;
				continue;
			}

			if (firstSize > firstMaxSize) {
				splitterPos += firstMaxSize - firstSize;
				continue;
			}

			if (secondSize < secondMinSize) {
				splitterPos -= secondMinSize - secondSize;
				continue;
			}

			if (secondSize > secondMaxSize) {
				splitterPos -= secondMaxSize - secondSize;
				continue;
			}
		}

		switch (direction) {
			case Horizontal:
				childElement[1].x = firstPos;
				childElement[1].setWidth(firstSize);
				childElement[2].x = secondPos;
				childElement[2].setWidth(secondSize);
				splitter.x = splitterPos;
			case Vertical:
				childElement[1].y = firstPos;
				childElement[1].setHeight(firstSize);
				childElement[2].y = secondPos;
				childElement[2].setHeight(secondSize);
				splitter.y = splitterPos;
		}
	}

	function onSplitterMove(newPos: Float) {
		splitterPos = Std.int(newPos);
		needReflow = true;
	}
}

#end