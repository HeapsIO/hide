package hide.comp;

enum ScrollRequest {
	Start;
	Middle;
	End;
	Auto; // try to preserve current scroll unless items goes out the visible window
}

private typedef Row = {
	root : js.html.Element,
	y : Float,
	height : Float,
	width : Float,
	stamp : Int,
}

/**
	Displays a list of items of variable height, only creating the elements of the visible ones.
	The scroll position is anchored on an item (`scrollIndex`) : heights of items out of view are never needed.
	Rows are absolutely positioned divs.
**/
class VirtualList<T> {
	public var element(default, null) : js.html.DivElement;

	public var generateItem(default, set) : (item : T) -> js.html.Element = null;

	/**
		How many pixels can be scrolled past the bottom of the last item.
	**/
	public var afterScroll(default, set) : Int = 0;

	var content : js.html.DivElement;
	var items : Array<T> = [];
	var rows = new js.lib.Map<T, Row>();
	var stamp = 0;

	var needRefresh = false;
	var refreshQueued = false;
	var scrollIndex : Int = 0;
	var itemPixelScroll : Float = 0;
	var prevScrollIndex : Int = -1;
	var prevItemPixelScroll : Float = 0;
	var scrollRequest : ScrollRequest = null;

	var scrollbar : js.html.DivElement;
	var scrollbarCursor : js.html.DivElement;

	var refreshTime = 0.0;

	public function new(?parent : js.html.Element) {
		var doc = js.Browser.document;
		element = doc.createDivElement();
		element.classList.add("hide-virtual-list");

		content = doc.createDivElement();
		content.classList.add("content");
		element.append(content);

		scrollbar = doc.createDivElement();
		scrollbar.classList.add("scrollbar");
		scrollbarCursor = doc.createDivElement();
		scrollbarCursor.classList.add("cursor");
		scrollbar.append(scrollbarCursor);
		element.append(scrollbar);

		function scrollFromPointer(e : js.html.PointerEvent) {
			if (items.length == 0)
				return;
			var rect = scrollbar.getBoundingClientRect();
			var id = Std.int((e.clientY - rect.top) / rect.height * (items.length - 1));
			scrollToIndex(hxd.Math.iclamp(id, 0, items.length - 1), Middle);
		}

		scrollbar.onpointerdown = (e : js.html.PointerEvent) -> {
			if (e.button != 0)
				return;
			scrollbar.setPointerCapture(e.pointerId);
			scrollFromPointer(e);
		}
		scrollbar.onpointermove = (e : js.html.PointerEvent) -> {
			if (scrollbar.hasPointerCapture(e.pointerId))
				scrollFromPointer(e);
		}

		element.addEventListener("wheel", (e : js.html.WheelEvent) -> {
			itemPixelScroll += e.deltaMode == js.html.WheelEvent.DOM_DELTA_PIXEL ? e.deltaY : e.deltaY * 25.0;
			refresh();
			e.preventDefault();
		}, {passive: false});

		new ResizeObserver((_, _) -> refresh()).observe(content);

		if (parent != null)
			parent.append(element);
	}

	function set_afterScroll(v) {
		refresh();
		return afterScroll = v;
	}

	function set_generateItem(v) {
		refresh();
		return generateItem = v;
	}

	/**
		Called for each visible element in the view each time something change.
	**/
	public dynamic function refreshItem(item : T, element : js.html.Element) : Void {
	}

	/**
		Called when the element representing `item` is removed (because it's no longer visible)
	**/
	public dynamic function onItemRemoved(item : T) : Void {
	}

	public function refresh() {
		needRefresh = true;
		if (refreshQueued)
			return;
		refreshQueued = true;
		var win = element.ownerDocument.defaultView ?? js.Browser.window;
		win.requestAnimationFrame((_) -> {
			refreshQueued = false;
			refreshInternal();
		});
	}

	public function clear() {
		for (row in rows)
			row.root.remove();
		rows.clear();
		refresh();
	}

	public function tryGetElement(item : T) : Null<js.html.Element> {
		return rows.get(item)?.root.firstElementChild;
	}

	public function setItems(items : Array<T>) : Void {
		this.items = items;
		scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length - 1);
		refresh();
	}

	public function scrollTo(item : T, request : ScrollRequest = Auto) {
		scrollToIndex(items.indexOf(item), request);
	}

	public function scrollToIndex(id : Int, request : ScrollRequest = Auto) {
		scrollRequest = request;
		prevScrollIndex = scrollIndex;
		scrollIndex = id;
		prevItemPixelScroll = itemPixelScroll;
		itemPixelScroll = 0;
		refresh();
	}

	function refreshInternal() {
		if (!needRefresh || generateItem == null || !element.isConnected)
			return;

		var start = js.Browser.window.performance.now();

		if (scrollRequest == Auto) {
			// We do one refresh, then check if the requested item is in that range.
			// If it's not in that range, we perform another refresh this time requesting
			// that our item appear at the top or the bottom
			var requestScrollIndex = scrollIndex;
			scrollIndex = prevScrollIndex;
			itemPixelScroll = prevItemPixelScroll;
			scrollRequest = null;

			doRefresh();

			var row = rows.get(items[requestScrollIndex]);
			if (row == null || row.y < 0 || row.y + row.height > content.clientHeight) {
				scrollRequest = requestScrollIndex <= prevScrollIndex ? Start : End;
				scrollIndex = requestScrollIndex;
				doRefresh();
			}
		}
		else {
			doRefresh();
		}

		refreshTime = js.Browser.window.performance.now() - start;
	}

	function doRefresh() {
		needRefresh = false;
		stamp++;

		var width = content.clientWidth;
		var maxY = content.clientHeight;
		var minY = 0;
		var layoutRows : Array<{index : Int, row : Row}> = [];

		if (items.length > 0 && maxY > 0) {
			scrollIndex = hxd.Math.iclamp(scrollIndex, 0, items.length - 1);

			function genItem(index : Int, above : Bool) : Row {
				var item = items[index];
				var row = rows.get(item);
				if (row == null) {
					var root = js.Browser.document.createDivElement();
					root.classList.add("row");
					root.append(generateItem(item));
					content.append(root);
					row = {root: root, y: 0, height: 0, width: -1, stamp: 0};
					rows.set(item, row);
				}

				refreshItem(item, row.root.firstElementChild);
				row.stamp = stamp;
				if (row.width != width) {
					row.width = width;
					row.root.style.width = width + "px";
				}
				row.height = row.root.getBoundingClientRect().height;

				if (above)
					layoutRows.unshift({index: index, row: row});
				else
					layoutRows.push({index: index, row: row});
				return row;
			}

			var current = genItem(scrollIndex, false);

			var startY : Float = switch (scrollRequest) {
				case Start: minY;
				case End: maxY - current.height;
				case Middle: (maxY + minY - current.height) * 0.5;
				case Auto: throw "error";
				case null: -itemPixelScroll;
			}
			startY = Math.round(startY);
			scrollRequest = null;

			current.y = startY;

			var finalOffset = 0.0;
			var topOffset = 0.0;
			var botOffset = current.height;

			var topIndex = scrollIndex - 1;
			var botIndex = scrollIndex + 1;

			var leftToProcess = true;
			inline function topY() return startY + topOffset + finalOffset;
			inline function botY() return startY + botOffset + finalOffset;

			while (leftToProcess) {
				leftToProcess = false;

				if (botY() < maxY && botIndex < items.length) {
					leftToProcess = true;
					var row = genItem(botIndex, false);
					row.y = startY + botOffset;
					botOffset += row.height;
					botIndex++;
				}

				// we reached the bottom
				if (botIndex >= items.length && botY() < maxY - afterScroll) {
					finalOffset = (maxY - afterScroll) - (startY + botOffset);
				}

				if (topY() > minY && topIndex >= 0) {
					leftToProcess = true;
					var row = genItem(topIndex, true);
					topOffset -= row.height;
					row.y = startY + topOffset;
					topIndex--;
				}

				// reached the top
				if (topIndex < 0 && topY() > minY) {
					finalOffset = minY - (startY + topOffset);
				}
			}

			if (finalOffset != 0) {
				for (line in layoutRows)
					line.row.y += finalOffset;
			}

			var maxVisible = layoutRows[layoutRows.length - 1].index;
			for (line in layoutRows) {
				var row = line.row;
				if (row.y <= 0 && row.y + row.height > 0) {
					scrollIndex = line.index;
					itemPixelScroll = -row.y;
				}

				if (row.y < maxY && row.y + row.height >= maxY) {
					maxVisible = line.index;
				}
			}

			var scrollbarHeight = maxY;
			var scrollbarMin = scrollIndex / (items.length - 1) * scrollbarHeight;
			var scrollbarMax = maxVisible / (items.length - 1) * scrollbarHeight;
			var avg = (scrollbarMax + scrollbarMin) / 2.0;
			var height = Math.max(10, (maxVisible - scrollIndex) / (items.length - 1) * scrollbarHeight);
			scrollbarCursor.style.top = (avg - height * 0.5) + "px";
			scrollbarCursor.style.height = height + "px";
			scrollbar.style.visibility = scrollbarMin > 0 || scrollbarMax < scrollbarHeight ? "visible" : "hidden";
		}

		rows.forEach((row, item, _) -> {
			if (row.stamp != stamp) {
				row.root.remove();
				rows.delete(item);
				onItemRemoved(item);
			}
		});

		for (line in layoutRows)
			line.row.root.style.transform = 'translateY(${line.row.y}px)';
	}
}
