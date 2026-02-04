package hrt.ui;


#if hui

enum ScrollRequest {
	Start;
	Middle;
	End;
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
	var scrollRequest : ScrollRequest = null;

	var customScrollbar: HuiElement;
	var customScrollbarCursor: HuiElement;

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
						element.dom.applyStyle(style);
					} else {
						itemContainer.addChild(element);
					}
					oldElements.remove(cast item);
					element.setWidth(Std.int(calculatedWidth));
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
					case End: maxY;
					case Middle: (maxY + minY - currentItem.calculatedHeight) * 0.5;
					case null: -itemPixelScroll;
				}
				trace(scrollIndex, startY);
				scrollRequest = null;

				currentItem.y = startY;

				var startY2 = startY + currentItem.calculatedHeight;

				var reachedBottom = false;

				var currentY = startY2;
				for (i in scrollIndex+1...items.length) {
					var item = genItem(i, false);
					item.y = currentY;
					currentY += item.calculatedHeight;
					if (currentY > maxY) {
						break;
					}
				}

				// fix list if it has gone out of bounds
				if (currentY <= maxY) {
					var currentY = maxY;
					for (i in 0...layoutLines.length) {
						var line = layoutLines[layoutLines.length - 1 - i];
						currentY -= line.element.calculatedHeight;
						line.element.y = currentY;
					}
					startY = currentY;
				}

				var currentY : Float = startY;
				var reachedTop = false;
				for (i in 0...scrollIndex) {
					var i2 = scrollIndex - 1 - i;
					var item = genItem(i2, true);
					currentY -= item.calculatedHeight;
					item.y = currentY;
					if (currentY < minY) {
						break;
					}
				}
				if (currentY >= minY) {
					var currentY = 0.0;
					for (line in layoutLines) {
						line.element.y = currentY;
						currentY += line.element.calculatedHeight;
					}
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

	public function setItems(items: Array<T>) : Void {
		this.items = items;
		needRefresh = true;
		scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length-1);
	}

	public function scrollTo(item: T, request: ScrollRequest = null) {
		scrollToIndex(items.indexOf(item), request);
	}

	public function scrollToIndex(id: Int, request: ScrollRequest = null) {
		scrollRequest = request;
		scrollIndex = id;
		itemPixelScroll = 0;
		needRefresh = true;
	}

	public var generateItem(default, set) : (item: T) -> HuiElement = null;

	function set_generateItem(v) {
		needRefresh = true;
		return generateItem = v;
	}
}


#end