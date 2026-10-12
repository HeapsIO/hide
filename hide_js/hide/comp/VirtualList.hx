package hide.comp;

enum ScrollRequest {
	Start;
	Middle;
	End;
	Auto; // try to preserve current scroll unless items goes out the visible window
}

/**
	Port of hrt.ui.HuiVirtualList : only the elements of the visible items exist, absolutely positioned from the
	scroll anchor (scrollIndex, itemPixelScroll), so items can have any height.
**/
class VirtualList<T> {
	public var element(default, null) : js.html.Element;
	var itemContainer : js.html.Element;
	var scrollbar : js.html.Element;
	var scrollbarCursor : js.html.Element;
	var resizeObserver : ResizeObserver;

	var items : Array<T> = [];
	var elements = new js.lib.Map<T, js.html.Element>();
	var keepLines = new js.lib.Map<T, Bool>();
	/** Height of the elements at their last refresh, to detect when they change **/
	var heights = new js.lib.Map<js.html.Element, Int>();
	/** Lines of the last refresh, top to bottom **/
	var layout : Array<{index: Int, y: Float, height: Int}> = [];
	/** Height of the items not measured yet **/
	var avgHeight = 20.0;

	var refreshQueued = false;
	var scrollIndex : Int = 0;
	var itemPixelScroll : Int = 0;
	var prevScrollIndex : Int = -1;
	var prevItemPixelScroll : Int = 0;
	var scrollRequest : ScrollRequest = null;
	var canScrollUp = false;
	var canScrollDown = false;

	public var generateItem(default, set) : (item: T) -> js.html.Element = null;

	/**
		How many pixels can be scrolled past the bottom of the last item.
	**/
	public var afterScroll(default, set) : Int = 0;

	function set_afterScroll(v) {
		refresh();
		return afterScroll = v;
	}

	function set_generateItem(v) {
		refresh();
		return generateItem = v;
	}

	/**
		called for each visible element in the view each time something change.
	**/
	public dynamic function refreshItem(item: T, element: js.html.Element) : Void {

	}

	/**
		Called when the element representing `item` is removed (because it's no longer visible)
	**/
	public dynamic function onItemRemoved(item: T) : Void {

	}

	public function refresh() {
		if (refreshQueued)
			return;
		refreshQueued = true;
		js.Browser.window.requestAnimationFrame((_) -> refreshInternal());
	}

	/**
		When enabled, the element of `item` is moved out of view instead of removed when it goes out of view.
	**/
	public function setKeepLine(item: T, enable: Bool) {
		if (enable)
			keepLines.set(item, true);
		else
			keepLines.delete(item);
		refresh();
	}

	public function clear() {
		for (element in elements)
			removeElement(element);
		elements.clear();
		refresh();
	}

	public function new(?parent: js.html.Element) {
		var doc = js.Browser.document;
		element = doc.createElement("virtual-list");
		itemContainer = doc.createElement("virtual-list-items");
		element.appendChild(itemContainer);
		if (parent != null)
			parent.appendChild(element);

		// resized lists and items need a new layout
		resizeObserver = new ResizeObserver((entries, _) -> {
			for (e in entries) {
				var el : js.html.Element = e.target;
				if (el == element || heights.get(el) != el.offsetHeight) {
					refresh();
					return;
				}
			}
		});
		resizeObserver.observe(element);

		{
			scrollbar = doc.createElement("virtual-list-scrollbar");
			element.appendChild(scrollbar);
			scrollbarCursor = doc.createElement("virtual-list-cursor");
			scrollbar.appendChild(scrollbarCursor);

			scrollbar.onpointerdown = (e: js.html.PointerEvent) -> {

				function scroll(e: js.html.PointerEvent) {
					var rect = scrollbar.getBoundingClientRect();
					var percent = (e.clientY - rect.top) / rect.height;
					var id = Std.int(percent * (items.length - 1));
					id = hxd.Math.iclamp(id, 0, (items.length - 1));
					scrollToIndex(id, Middle);
				}

				scroll(e);

				scrollbar.setPointerCapture(e.pointerId);
				scrollbar.onpointermove = scroll;
				scrollbar.onlostpointercapture = (_) -> scrollbar.onpointermove = null;
			}
		}

		element.onwheel = wheel;
	}

	public function tryGetElement(item: T) : Null<js.html.Element> {
		return elements.get(item);
	}

	function wheel(e: js.html.WheelEvent) {
		if (e.deltaY > 0 ? !canScrollDown : !canScrollUp)
			return;
		itemPixelScroll += Std.int(e.deltaY);

		refresh();
		e.preventDefault();
		e.stopPropagation();
	}

	function refreshInternal() {
		refreshQueued = false;
		if (generateItem == null)
			return;
		if (scrollRequest == Auto) {
			// We do one refresh, then check if the requested item is in that range.
			// If it's not in that range, we perform another refresh this time requesting
			// that our item appear at the top or the bottom
			var requestScrollIndex = scrollIndex;
			scrollIndex = prevScrollIndex;
			itemPixelScroll = prevItemPixelScroll;
			scrollRequest = null;

			doRefresh();
			var line = Lambda.find(layout, (l) -> l.index == requestScrollIndex);
			if (line == null || line.y < 0 || line.y + line.height > element.clientHeight) {
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

	function doRefresh() {
		var maxY = element.clientHeight;
		var minY = 0;
		canScrollUp = false;
		canScrollDown = false;
		var lastLayout = layout;
		layout = [];

		if (items.length > 0) {
			scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length-1);

			function lastHeight(index: Int) : Int {
				var line = lastLayout.length > 0 ? lastLayout[index - lastLayout[0].index] : null;
				return line != null ? line.height : Std.int(avgHeight);
			}

			// move the anchor past the items scrolled out of view, so they aren't generated
			if (scrollRequest == null) {
				while (scrollIndex < items.length - 1 && itemPixelScroll >= lastHeight(scrollIndex)) {
					itemPixelScroll -= lastHeight(scrollIndex);
					scrollIndex++;
				}
				while (scrollIndex > 0 && itemPixelScroll < 0) {
					scrollIndex--;
					itemPixelScroll += lastHeight(scrollIndex);
				}
			}

			// heights of the items refreshed by this layout, by index
			var refreshed = new Map<Int, Int>();

			function genItem(index: Int) : js.html.Element {
				var item = items[index];

				var element = elements.get(item);
				if (element == null) {
					element = generateItem(item);
					elements.set(item, element);
					itemContainer.appendChild(element);
					resizeObserver.observe(element);
				}
				refreshItem(item, element);
				return element;
			}

			var startY = 0.0;
			var finalOffset = 0.0;
			var topOffset = 0.0;
			var botOffset = 0.0;
			var topIndex = 0;
			var botIndex = 0;
			inline function topY() {return startY + topOffset + finalOffset;};
			inline function botY() {return startY + botOffset + finalOffset;};

			/*
				Unlike in h2d, reading the height of an element forces a layout. So the lines are laid out with the
				estimated height of the items not refreshed yet, then these items are refreshed and measured at once,
				until all the items of the layout are measured.
			*/
			while (true) {
				var missing = [];
				function height(index: Int) : Float {
					var h = refreshed.get(index);
					if (h != null)
						return h;
					missing.push(index);
					return lastHeight(index);
				}

				var currentHeight = height(scrollIndex);

				startY = switch (scrollRequest) {
					case Start: minY;
					case End: maxY - currentHeight;
					case Middle: (maxY + minY - currentHeight) * 0.5;
					case Auto: throw "error";
					case null: -itemPixelScroll;
				}
				startY = hxd.Math.round(startY);

				finalOffset = 0.0;
				topOffset = 0.0;
				botOffset = currentHeight;

				topIndex = scrollIndex - 1;
				botIndex = scrollIndex + 1;

				var leftToProcess = true;
				while(leftToProcess) {
					leftToProcess = false;

					if (botY() < maxY && botIndex < items.length) {
						leftToProcess = true;
						botOffset += height(botIndex);
						botIndex ++;
					}

					// we reached the bottom
					if (botIndex >= items.length && botY() < maxY - afterScroll) {
						finalOffset = (maxY - afterScroll) - (startY + botOffset);
					}

					if (topY() > minY && topIndex >= 0) {
						leftToProcess = true;
						topOffset -= height(topIndex);
						topIndex--;
					}

					// reached the top
					if (topIndex < 0 && topY() > minY) {
						finalOffset = minY - (startY + topOffset);
						// the lines moved up, fill the bottom
						leftToProcess = leftToProcess || botIndex < items.length;
					}
				}

				if (missing.length == 0)
					break;

				var generated = [for (index in missing) genItem(index)];
				for (i => index in missing) {
					var h = generated[i].offsetHeight;
					refreshed.set(index, h);
					heights.set(generated[i], h);
				}
			}
			scrollRequest = null;

			canScrollUp = topIndex >= 0 || topY() < minY;
			canScrollDown = botIndex < items.length || botY() > maxY - afterScroll;

			var y = topY();
			for (index in topIndex + 1...botIndex) {
				var h = refreshed.get(index);
				layout.push({index: index, y: y, height: h});
				elements.get(items[index]).style.transform = 'translateY(${y}px)';
				y += h;
			}

			var maxVisible = layout[layout.length-1].index;
			for (line in layout) {
				if (line.y <= 0 && line.y + line.height > 0) {
					scrollIndex = line.index;
					itemPixelScroll = -Std.int(line.y);
				}

				if (line.y < maxY && line.y + line.height >= maxY) {
					maxVisible = line.index;
				}
			}

			var count = 0;
			var total = 0;
			for (h in refreshed) {
				count++;
				total += h;
			}
			avgHeight = total / count;

			var scrollBarHeight = maxY;

			var scrollbarMin = scrollIndex / (items.length-1) * scrollBarHeight;
			var scrollbarMax = (maxVisible) / (items.length-1) * scrollBarHeight;
			var avg = (scrollbarMax + scrollbarMin) / 2.0;
			var height = hxd.Math.imax(10,Std.int(((maxVisible-scrollIndex) / (items.length-1)) * scrollBarHeight));
			scrollbarCursor.style.transform = 'translateY(${avg - height*0.5}px)';
			scrollbarCursor.style.height = '${height}px';

			scrollbar.style.display = scrollbarMin > 0 || scrollbarMax < scrollBarHeight ? null : "none";
		}

		var visible = new js.lib.Map<T, Bool>();
		for (line in layout)
			visible.set(items[line.index], true);
		for (item => old in elements) {
			if (visible.has(item))
				continue;
			if (keepLines.has(item)) {
				// not display none, the browser would blur the focused element
				old.style.transform = "translateY(-100000px)";
				continue;
			}
			removeElement(old);
			elements.delete(item);
			onItemRemoved(item);
		}
	}

	function removeElement(element: js.html.Element) {
		element.remove();
		resizeObserver.unobserve(element);
		heights.delete(element);
	}

	public function setItems(items: Array<T>) : Void {
		this.items = items;
		for (item => _ in keepLines)
			if (!items.contains(item))
				keepLines.delete(item);
		refresh();
		scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length-1);
	}

	public function scrollTo(item: T, request: ScrollRequest = Auto) {
		scrollToIndex(items.indexOf(item), request);
	}

	public function scrollToIndex(id: Int, request: ScrollRequest = Auto) {
		// a pending request already replaced the current scroll
		if (scrollRequest == null) {
			prevScrollIndex = scrollIndex;
			prevItemPixelScroll = itemPixelScroll;
		}
		scrollRequest = request;
		scrollIndex = id;
		itemPixelScroll = 0;
		refresh();
	}
}
