package hrt.ui;


#if hui

class HuiVirtualList<T> extends HuiElement {
	static var SRC =
		<hui-virtual-list>
			<hui-element id='item-container'/>
		</hui-virtual-list>


	var items : Array<T> = [];
	var elements : Map<{}, HuiElement> = [];

	var needRefresh = true;
	var scrollIndex : Int = 10;
	var itemPixelScroll : Int = 0;
	var requestedScroll : Int = 0;

	function new(?parent) {
		super(parent);
		initComponent();

		onBeforeReflow = () -> {
			needRefresh = true;
		}
	}

	/**
		Prevent need reflow propagation (our layout don't depends of our children)
	**/
	override function contentChanged(s : h2d.Object) {
		onContentChanged();
	}


	override function sync(ctx:h2d.RenderContext) {

		onWheel = wheel;

		refreshInternal();

		super.sync(ctx);

	}

	function wheel(e: hxd.Event) {
		requestedScroll = Std.int(e.wheelDelta* 10.0) ;
		needRefresh = true;
		e.propagate = false;
	}

	function refreshInternal() {
		if (needRefresh) {
			var style = uiBase.style;
			needRefresh = false;

			var oldElements = elements.copy();
			var newScrollIndex = scrollIndex;

			itemPixelScroll = itemPixelScroll + requestedScroll;
			if (scrollIndex == 0 && itemPixelScroll < 0) {
				itemPixelScroll = 0;
			}

			var nextScrollIndex = scrollIndex;
			var nextItemPixelScroll = itemPixelScroll;

			itemContainer.removeChildren();

			function genItem(index: Int, height: Float, above: Bool) : HuiElement {
				var item = items[index];

				var element = elements.get(cast item);
				if (element == null) {
					element = generateItemInternal(item);
					//elements.set(cast item, element);
					itemContainer.addChild(element);
					itemContainer.getProperties(element).isAbsolute = true;

					// Force apply style because we need the accura
					element.dom.applyStyle(style, false);
				} else {
					itemContainer.addChild(element);
				}
				oldElements.remove(cast item);
				element.setWidth(Std.int(calculatedWidth-25));
				element.x = 0;
				element.y = height;
				element.reflow();

				if (above) {
					element.y -= element.calculatedHeight;
				}

				if (element.y <= 0 && element.y + element.calculatedHeight > 0) {
					nextScrollIndex = index;
					nextItemPixelScroll = -Std.int(element.y);
				}




				return element;
			}


			var minY = 0;
			var maxY = calculatedHeight;

			requestedScroll = 0;

			var startY : Float = -itemPixelScroll;
			var currentItem = genItem(scrollIndex, startY, false);
			currentItem.x += 10;

			var startY2 = startY + currentItem.calculatedHeight;

			var currentY = startY2;
			for (i in scrollIndex+1...items.length) {
				var item = genItem(i, currentY, false);
				currentY += item.calculatedHeight;
				if (currentY > maxY) {
					break;
				}
			}

			var currentY = startY;
			for (i in 0...scrollIndex) {
				var i2 = scrollIndex - 1 - i;
				var item = genItem(i2, currentY, true);
				currentY = item.y;
				if (currentY < minY) {
					break;
				}
			}

			for (old in oldElements) {
				old.remove();
			}

			scrollIndex = nextScrollIndex;
			itemPixelScroll = nextItemPixelScroll;

		}
	}

	function refreshItem(item: T) : Void {
		var element = elements.get(cast item);
		if (element != null) {
			element.remove();
			elements.remove(cast item);
		}
	}

	dynamic function generateItemInternal(item: T) : HuiElement {
		var item = generateItem(item);
		var container = new HuiElement();
		container.addChild(item);
		return container;
	}

	dynamic function generateItem(item: T) : HuiElement {
		return null;
	}
}

#end