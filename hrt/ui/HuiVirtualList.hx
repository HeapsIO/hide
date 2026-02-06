package hrt.ui;


#if hui

enum ScrollRequest {
	Start;
	Middle;
	End;
	Auto; // try to preserve current scroll unless items goes out the visible window
}

class HuiVirtualList<T> extends HuiElement {
	static var SRC =
		<hui-virtual-list>
			<hui-element id='item-container'/>
		</hui-virtual-list>


	var items : Array<T> = [];
	var elements : Map<{}, HuiElement> = [];

	var needRefresh = true;
	var scrollIndex : Int = 0;
	var itemPixelScroll : Int = 0;
	var prevScrollIndex : Int = -1;
	var prevItemPixelScroll : Int = 0;
	var scrollRequest : ScrollRequest = null;

	var customScrollbar: HuiElement;
	var customScrollbarCursor: HuiElement;

	public var generateItem(default, set) : (item: T) -> HuiElement = null;

	function set_generateItem(v) {
		needRefresh = true;
		return generateItem = v;
	}

	/**
		called for each visible element in the view each time something change.
	**/
	public dynamic function refreshItem(item: T, element: HuiElement) : Void {

	}

	function new(?parent) {
		super(parent);
		initComponent();

		onBeforeReflow = () -> {
			needRefresh = true;
		}

		{
			customScrollbar = makeScrollBar();
			addChild(customScrollbar);
			customScrollbarCursor = makeScrollBarCursor();
			customScrollbar.addChild(customScrollbarCursor);

			customScrollbar.onPush = (e) -> {

				function scroll(e) {
					var y = getScene().mouseY - customScrollbar.absY;
					var percent = y / customScrollbar.innerHeight;
					var id = Std.int(percent * (items.length - 1));
					id = hxd.Math.iclamp(id, 0, (items.length - 1));
					scrollToIndex(id, Middle);
				}

				scroll(e);

				getScene().startCapture((e) -> {
					scroll(e);
					if (e.kind == ERelease || e.kind == EReleaseOutside || !hxd.Key.isDown(hxd.Key.MOUSE_LEFT)) {
						getScene().stopCapture();
					}
				});
			}

			var p = getProperties(customScrollbar);
			p.isAbsolute = true;
			p.horizontalAlign = Right;
			p.verticalAlign = Top;

			customScrollbar.getProperties(customScrollbarCursor).isAbsolute = true;
		}

		makeInteractive();
		interactive.propagateEvents = true;
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
		itemPixelScroll += Std.int(e.wheelDelta* 25.0) ;

		needRefresh = true;
		e.propagate = false;
	}

	function refreshInternal() {
		if (needRefresh && generateItem != null) {
			if (scrollRequest == Auto) {
				// We do one refresh, then check if the requested item is in that range.
				// If it's not in that range, we perform another refresh this time requesting
				// that our item appear at the top or the bottom
				var requestScrollIndex = scrollIndex;
				var requestItemPixelScroll = itemPixelScroll;
				scrollIndex = prevScrollIndex;
				itemPixelScroll = prevItemPixelScroll;
				scrollRequest = null;

				doRefresh();
				var requestedItem = items[requestScrollIndex];
				var element = elements.get(cast requestedItem);

				var shouldRefreshAgain = false;
				if (element != null) {
					var minY = 0;
					var maxY = calculatedHeight;

					if (element.y < minY || element.y + element.calculatedHeight > maxY) {
						shouldRefreshAgain = true;
					}
				} else {
					shouldRefreshAgain = true;
				}

				if (shouldRefreshAgain) {
					if (requestScrollIndex <= prevScrollIndex) {
						scrollRequest = Start;
					} else {
						scrollRequest = End;
					}
					scrollIndex = requestScrollIndex;

					doRefresh();
				}
			}
			else {
				doRefresh();
			}
		}
	}

	function doRefresh() {
		var style = uiBase.style;
		needRefresh = false;

		var oldElements = elements.copy();

		if (items.length > 0) {
			scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length-1);

			//itemContainer.removeChildren();

			var layoutLines : Array<{index: Int, element: HuiElement}> = [];

			function genItem(index: Int, above: Bool) : HuiElement {
				var item = items[index];

				var element = elements.get(cast item);
				if (element == null) {
					element = generateItemInternal(item);
					elements.set(cast item, element);
					itemContainer.addChild(element);
					itemContainer.getProperties(element).isAbsolute = true;

					// Force apply style because we need the accurate font info for the layout
					// element.dom.applyStyle(style);
				} else {
					itemContainer.addChild(element);
				}
				refreshItem(item, cast element.childElements[0]);
				oldElements.remove(cast item);
				element.setWidth(Std.int(calculatedWidth));
				element.dom.applyStyle(style);
				element.reflow();
				element.x = 0;
				if (above) {
					layoutLines.unshift({index: index, element: element});
				} else {
					layoutLines.push({index: index, element: element});
				}

				return element;
			}


			var minY = 0;
			var maxY = calculatedHeight;

			var currentItem = genItem(scrollIndex, false);

			var startY : Float = switch (scrollRequest) {
				case Start: minY;
				case End: maxY - currentItem.calculatedHeight;
				case Middle: (maxY + minY - currentItem.calculatedHeight) * 0.5;
				case Auto: throw "error";
				case null: -itemPixelScroll;
			}
			scrollRequest = null;

			currentItem.y = startY;


			var finalOffset = 0.0;
			var topOffset = 0.0;
			var botOffset = currentItem.calculatedHeight;

			var topIndex = scrollIndex - 1;
			var botIndex = scrollIndex + 1;

			var leftToProcess = true;
			inline function topY() {return startY + topOffset + finalOffset;};
			inline function botY() {return startY + botOffset + finalOffset;};

			while(leftToProcess) {
				leftToProcess = false;

				if (botY() < maxY && botIndex < items.length) {
					leftToProcess = true;
					var item = genItem(botIndex, false);
					item.y = startY + botOffset;
					botOffset += item.calculatedHeight;
					botIndex ++;
				}

				// we reached the bottom
				if (botIndex >= items.length && botY() < maxY) {
					finalOffset = maxY - (startY + botOffset);
				}

				if (topY() > minY && topIndex >= 0) {
					leftToProcess = true;
					var item = genItem(topIndex, true);
					topOffset -= item.calculatedHeight;
					item.y = startY + topOffset;
					topIndex--;
				}

				// reached the top
				if (topIndex < 0 && topY() > minY) {
					finalOffset = minY - (startY + topOffset);
				}
			}

			if (finalOffset != 0) {
				for (line in layoutLines) {
					line.element.y += finalOffset;
				}
			}

			for (line in layoutLines) {
				line.element.reflow();
			}

			var maxVisible = layoutLines[layoutLines.length-1].index;
			for (i => line in layoutLines) {
				if (line.element.y <= 0 && line.element.y + line.element.calculatedHeight > 0) {
					scrollIndex = line.index;
					itemPixelScroll = -Std.int(line.element.y);
				}

				if (line.element.y < calculatedHeight && line.element.y + line.element.calculatedHeight >= maxY) {
					maxVisible = line.index;
				}
			}

			customScrollbar.setHeight(Std.int(calculatedHeight));

			var scrollBarHeight = customScrollbar.innerHeight;

			var scrollbarMin = scrollIndex / (items.length-1) * scrollBarHeight;
			var scrollbarMax = (maxVisible) / (items.length-1) * scrollBarHeight;
			var avg = (scrollbarMax + scrollbarMin) / 2.0;
			var height = hxd.Math.imax(10,Std.int(((maxVisible-scrollIndex) / (items.length-1)) * scrollBarHeight));
			customScrollbarCursor.y = avg - height*0.5;
			customScrollbarCursor.setHeight(height);
		}

		for (item => old in oldElements) {
			old.remove();
			elements.remove(cast item);
		}
	}


	function generateItemInternal(item: T) : HuiElement {
		var item = generateItem(item);
		var container = new HuiElement();
		container.addChild(item);
		return container;
	}

	public function setItems(items: Array<T>) : Void {
		this.items = items;
		needRefresh = true;
		scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length-1);
	}

	public function scrollTo(item: T, request: ScrollRequest = Auto) {
		scrollToIndex(items.indexOf(item), request);
	}

	public function scrollToIndex(id: Int, request: ScrollRequest = Auto) {
		scrollRequest = request;
		prevScrollIndex = scrollIndex;
		scrollIndex = id;
		prevItemPixelScroll = itemPixelScroll;
		itemPixelScroll = 0;
		needRefresh = true;
	}
}


#end