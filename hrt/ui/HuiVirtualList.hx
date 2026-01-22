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

	function new(?parent) {
		super(parent);
		initComponent();

		onAfterReflow = () -> {
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
		super.sync(ctx);

		onWheel = wheel;

		refreshInternal();
	}

	function wheel(e: hxd.Event) {
		itemPixelScroll -= Std.int(e.wheelDelta* 10.0) ;
		needRefresh = true;
	}

	function refreshInternal() {
		if (needRefresh) {
			needRefresh = false;

			var oldElements = elements.copy();
			var newScrollIndex = scrollIndex;

			var hl2 = calculatedHeight/2;
			var startY = calculatedHeight/2 + itemPixelScroll;
			var nextScrollIndex = scrollIndex;
			var nextItemPixelScroll = itemPixelScroll;

			function genItem(index: Int, height: Float) : Float {
				var item = items[index];

				var element = elements.get(cast item) ?? generateItem(item);
				elements.set(cast item, element);
				oldElements.remove(cast item);
				element.x = 0;
				element.y = height;
				element.maxWidth = Std.int(calculatedWidth);
				itemContainer.addChild(element);
				element.reflow();

				var h2 = element.calculatedHeight;
				if (height < hl2 && height+h2 >= hl2) {
					nextScrollIndex = index;
					nextItemPixelScroll = -Std.int(height - hl2);
					trace(nextScrollIndex,nextItemPixelScroll);
				}

				return h2;
			}

			var relY = startY;
			for (i in scrollIndex...items.length) {
				relY += genItem(i, relY);
				if (relY > calculatedHeight) {
					break;
				}
			}

			relY = startY;
			// for (i in 1...scrollIndex) {
			// 	var i2 = scrollIndex - i;
			// 	var h = genItem(i2, relY);
			// 	if (relY-h < 0)
			// 		break;
			// 	relY -= h;
			// }

			for (old in oldElements) {
				old.remove();
			}
		}
	}

	function refreshItem(item: T) : Void {
		var element = elements.get(cast item);
		if (element != null) {
			element.remove();
			elements.remove(cast item);
		}
	}

	dynamic function generateItem(item: T) : HuiElement {
		return null;
	}
}

#end