package hide.comp;

enum GalleryRefreshFlag {
	Search;
	Items;
	RegenHeader;
	FocusCurrent;
}

typedef GalleryRefreshFlags = haxe.EnumFlags<GalleryRefreshFlag>;

typedef GalleryItemData<GalleryItem> = {item: GalleryItem, name: String, element: js.html.Element, thumbnailStringCache: String, iconStringCache: String, ranges: hide.comp.FancySearch.SearchRanges};

class FancyGallery<GalleryItem> extends hide.comp.Component {

	var currentData : Array<GalleryItemData<GalleryItem>> = [];
	var itemMap : Map<{}, GalleryItemData<GalleryItem>> = [];
	var itemContainer : js.html.Element;
	var scroll : js.html.Element;
	var selection : Map<{}, Bool> = [];

	var tooltip : FancyTooltip;

	var lastHeight : Float = 0;
	var mouseOver : Bool = false;

	var lastSavedZoomPercent : Null<Float> = null;

	var zoom : Int = 5;
	static final zoomLevels = [0, 32, 64, 96, 128,192, 256, 384, 512];
	var itemHeightPx = 128;
	var itemWidthPx = 128;
	static final itemTitleHeight = 32;
	static final zoomedThumbnailSize = 512;
	static final zoomedThumbnailMargin = 32;

	var details = false;

	var currentItem(default, set) : GalleryItemData<GalleryItem>;
	function set_currentItem(v) {
		currentItem = v;
		queueRefresh(FocusCurrent);
		return currentItem;
	}

	var currentVisible(default, set) : Bool = false;

	function set_currentVisible(v) {
		currentVisible = v;
		if (currentVisible)
			queueRefresh(FocusCurrent);
		else
			queueRefresh();
		return currentVisible;
	}

	public function new(parent: Element, el: Element) {
		saveDisplayKey = "fancyGallery";
		if (el != null) {
			if (el.get(0).tagName != "FANCY-GALLERY") {
				throw "el must be a fancy-gallery node";
			}
		}
		else {
			el = new Element('<fancy-gallery></fancy-gallery>');
		}

		super(parent, el);
		element.html("
			<fancy-scroll>
				<fancy-item-container>
				</fancy-item-container>
			</fancy-scroll>
		");

		tooltip = new FancyTooltip();

		zoom = getDisplayState("zoom") ?? zoom;

		var htmlElem = el.get(0);
		htmlElem.tabIndex = -1;

		htmlElem.onkeydown = inputHandler;

		htmlElem.onmousemove = (e:js.html.MouseEvent) -> {
			var x = if (details) e.clientX + zoomedThumbnailMargin else e.clientX - Std.int(zoomedThumbnailSize/2);
			tooltip.x = hxd.Math.iclamp(x, zoomedThumbnailMargin, Std.int(js.Browser.window.innerWidth) - zoomedThumbnailSize - zoomedThumbnailMargin);
			tooltip.y = hxd.Math.iclamp(e.clientY - Std.int(zoomedThumbnailSize/2), zoomedThumbnailMargin, Std.int(js.Browser.window.innerHeight) - zoomedThumbnailSize - itemTitleHeight - zoomedThumbnailMargin);
			if (e.altKey) {
				tooltip.show();
			} else {
				tooltip.hide();
			}
		};

		htmlElem.onmouseenter = (e:js.html.MouseEvent) -> {
			mouseOver = true;
		}

		htmlElem.onmouseleave = (e:js.html.MouseEvent) -> {
			mouseOver = false;
			tooltip.hide();
		}

		js.Browser.document.addEventListener("keydown", (e: js.html.KeyboardEvent) -> {
			if (mouseOver && e.key == "Alt") {
				tooltip.show();
			}
		});
		js.Browser.document.addEventListener("keyup", (e: js.html.KeyboardEvent) -> {
			if (e.key == "Alt") {
				tooltip.hide();
			}
		});

		var resizeObserver = new hide.comp.ResizeObserver((_, _) -> {
			queueRefresh();
		});
		resizeObserver.observe(element.get(0));

		itemContainer = el.find("fancy-item-container").get(0);

		itemContainer.onwheel = (e: js.html.WheelEvent) -> {
			if (e.ctrlKey) {
				e.preventDefault();
				e.stopPropagation();

				if (e.deltaY < 0) {
					setZoom(zoom + 1);
				} else if (e.deltaY > 0) {
					setZoom(zoom - 1);
				}
			}
		}

		itemContainer.onblur = (e: js.html.FocusEvent) -> {
			if (itemContainer.contains(cast e.relatedTarget)) {
				currentVisible = false;
				currentItem = null;
			};
		}

		itemContainer.onclick = (e) -> {
			currentVisible = false;
		}

		itemContainer.oncontextmenu = contextMenuHandler.bind(null);
		scroll = el.find("fancy-scroll").get(0);

		scroll.onscroll = (e) -> queueRefresh();
	}

	public function setZoom(newLevel: Int) {
		lastSavedZoomPercent = (scroll.scrollTop + scroll.getBoundingClientRect().height / 2) / scroll.scrollHeight;
		zoom = hxd.Math.iclamp(newLevel, 0, zoomLevels.length-1);
		saveDisplayState("zoom", zoom);
		queueRefresh();
	}

	var refreshQueued : Bool = false;
	var currentRefreshFlags : GalleryRefreshFlags = GalleryRefreshFlags.ofInt(0);

	public function queueRefresh(flag: GalleryRefreshFlag = null) {
		if (flag != null) {
			currentRefreshFlags.set(flag);
		}
		if (!refreshQueued) {
			refreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onRefreshInternal());
		}
	}

	public dynamic function getItems() : Array<GalleryItem> {
		return [];
	}

	public dynamic function getItemRanges(item: GalleryItem) : hide.comp.FancySearch.SearchRanges {
		return [];
	}

	public dynamic function getName(item: GalleryItem) : String {
		return "";
	}

	public dynamic function getThumbnail(item: GalleryItem) : String {
		return null;
	}

	public dynamic function getIcon(item: GalleryItem) : String {
		return null;
	}

	public dynamic function onDoubleClick(item: GalleryItem) : Void {
	}

	/**
		Custom keyboard handler, register your shortcuts here
	**/
	public dynamic function onKeyPress(event: js.html.KeyboardEvent) : Bool {
		return false;
	}

	/**
		Called when an item becomes visible on screen due to scrolling or other things.
	**/
	public dynamic function visibilityChanged(item: GalleryItem, isVisible: Bool) : Void {

	}

	/**
		Called when the user right click an item (or the background) of the gallery.
		`item` will be null if the background was clicked. Default is do nothing
	**/
	public dynamic function onContextMenu(item: GalleryItem, event : js.html.MouseEvent) {
		event.stopPropagation();
		event.preventDefault();
	}

	/**
		Drag and drop interface.
		Set this struct with all of it's function callback to handle drag and drop inside your tree.
	**/
	public var dragAndDropInterface :
	{
		/**
			Called when the user starts a drag and drop operation on `item`.
			Fill dataTransfer with the information you want to transfer, you can use getSelectedItems to handle dragging more than
			one item at a time.
			Return `true` if the drag operation is allowed, and `false` to cancel it
		**/
		onDragStart: (item: GalleryItem, dataTransfer: js.html.DataTransfer) -> Bool,

		// /**
		// 	Called when the user hovers on `target` with a drag and drop operation. You need to return what drop orperation is allowed
		// 	on the given object
		// **/
		// getItemDropFlags: (target: TreeItem, dataTransfer: js.html.DataTransfer) -> DropFlags,

		// /**
		// 	Called when the user drops an item on `target` and getItemDropFlags returned at least one valid flag.
		// 	`where` tells you where the item was dropped, and you can use `dataTransfer` to know what was dropped
		// **/
		// onDrop: (target: TreeItem, where: DropOperation, dataTransfer: js.html.DataTransfer) -> Void
	} = null;

	public function rebuild() {
		queueRefresh(Items);
		queueRefresh(Search);
		queueRefresh(RegenHeader);
	}

	public function clearSelection() {
		selection.clear();
		queueRefresh();
	}

	function setSelection(data: GalleryItemData<GalleryItem>, select: Bool) {
		if (select) {
			selection.set(cast data, true);
		} else {
			selection.remove(cast data);
		}
	}

	public function getSelectedItems() {
		return [for (item => _ in selection) (cast item:GalleryItemData<GalleryItem>).item];
	}

	public function selectItem(item: GalleryItem) {
		clearSelection();
		var data = itemMap.get(cast item);
		if (data == null) {
			return;
		}
		setSelection(data, true);
		currentItem = data;
	}

	function dataClickHandler(data: GalleryItemData<GalleryItem>, event: js.html.MouseEvent) : Void {
		if (!event.ctrlKey) {
			clearSelection();
		}

		var currentIndex = currentData.indexOf(currentItem);
		if (event.shiftKey && currentIndex >= 0) {
			var newIndex = currentData.indexOf(data);

			var min = hxd.Math.imin(currentIndex, newIndex);
			var max = hxd.Math.imax(currentIndex, newIndex);

			for (i in min...max + 1) {
				setSelection(currentData[i], true);
			}
		} else {
			setSelection(data, !selection.exists(cast data));
		}

		if (!(event.shiftKey && !event.ctrlKey) || currentItem == null)
			currentItem = data;
		//onSelectionChanged();

		queueRefresh();
	}

	public function rename(item: GalleryItem, onFinished : (newName:String) -> Void) {
		var data = itemMap.get(cast item);
		var name = data.element.querySelector("fancy-name");
		name.contentEditable = "plaintext-only";
		var editable = new ContentEditable(null, new Element(data.element.querySelector("fancy-name")));

		editable.onCancel = () -> {
			queueRefresh(RegenHeader);
			element.focus();
		}

		editable.onChange = (newValue) -> {
			onFinished(name.textContent);
			queueRefresh(RegenHeader);
			element.focus();
		}

		editable.element.focus();
	}

	/**
		Never call this directly
	**/
	function onRefreshInternal() {
		refreshQueued = false;

		var margin = 8;

		var bounds = scroll.getBoundingClientRect();

		details = zoom == 0;
		itemWidthPx = zoomLevels[zoom];
		itemHeightPx = itemWidthPx + itemTitleHeight;
		if (details) {
			margin = 0;
			itemHeightPx = 16;
			itemWidthPx = hxd.Math.floor(bounds.width);
		}

		if (currentRefreshFlags.has(Items)) {
			rebuildItems();
		}

		var oldChildren = [for (node in itemContainer.childNodes) node];

		var numData = currentData.length;

		var itemsPerRow = hxd.Math.imax(hxd.Math.floor((bounds.width - margin) / (itemWidthPx + margin)), 1);

		var height = hxd.Math.ceil(numData / itemsPerRow) * (itemHeightPx + margin) + margin;
		if (height != lastHeight) {
			itemContainer.style.height = '${height}px';
			lastHeight = height;
		}

		// We might need to recompute the scroll height so we call getBoundingClientRect again
		var scrollHeight = scroll.getBoundingClientRect().height;

		if (currentRefreshFlags.has(FocusCurrent)) {
			var currentIndex = currentData.indexOf(currentItem);

			if (currentIndex >= 0) {
				var currentHeight = (hxd.Math.floor(currentIndex / itemsPerRow)) * (itemHeightPx + margin);
				if (currentHeight < scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight);
				}

				if (currentHeight + itemHeightPx - scrollHeight > scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight + itemHeightPx - scrollHeight);
				}
			}
		}

		if (lastSavedZoomPercent != null) {
			var newScrollTop = lastSavedZoomPercent * scroll.scrollHeight - scrollHeight / 2;
			lastSavedZoomPercent = null;

			scroll.scrollTo(scroll.scrollLeft, newScrollTop);
		}

		var clipStart = scroll.scrollTop;
		var clipEnd = scrollHeight + clipStart;
		var itemStart = hxd.Math.floor((clipStart-margin) / (itemHeightPx+margin)) * itemsPerRow;
		var itemEnd = hxd.Math.ceil((clipEnd-margin) / (itemHeightPx+margin)) * itemsPerRow;


		for (index in hxd.Math.imax(itemStart, 0) ... hxd.Math.imin(currentData.length, itemEnd)) {
			var data = currentData[index];
			var element = getElement(data);

			element.style.left = '${((index % itemsPerRow)) * (itemWidthPx + margin) + margin}px';
			element.style.top = '${hxd.Math.floor(index / itemsPerRow) * (itemHeightPx + margin) + margin}px';

			if (!oldChildren.remove(element)) {
				itemContainer.appendChild(element);
				visibilityChanged(data.item, true);
			}
		}

		for (oldChild in oldChildren) {
			if (itemContainer.contains(oldChild)) {
				itemContainer.removeChild(oldChild);
				var data : GalleryItemData<GalleryItem> = untyped oldChild.__data;
				if (data != null) {
					visibilityChanged(data.item, false);
				}
			}
		}

		currentRefreshFlags = GalleryRefreshFlags.ofInt(0);
	}

	function contextMenuHandler(item: GalleryItem, event: js.html.MouseEvent) {
		onContextMenu(item, event);
	}

	function setupDragAndDrop(data : GalleryItemData<GalleryItem>) {
		if (dragAndDropInterface == null)
			return;

		data.element.draggable = true;
		data.element.ondragstart = (e:js.html.DragEvent) -> {
			if (!selection.get(cast data)) {
				clearSelection();
				setSelection(data, true);
			}

			if (dragAndDropInterface.onDragStart(data.item, e.dataTransfer)) {
				e.dataTransfer.effectAllowed = "move";
				e.dataTransfer.setDragImage(data.element, 0,0);
			} else {
				e.preventDefault();
			}
		}
	}

	function getElement(data : GalleryItemData<GalleryItem>, tooltip = false) : js.html.Element {
		if (!tooltip && currentRefreshFlags.has(RegenHeader) && data.element != null) {
			data.element.remove();
			data.element = null;
		}

		var genElement = !tooltip ? data.element : null;
		if (genElement == null) {
			genElement = js.Browser.document.createElement("fancy-item");
			if (!tooltip)
				data.element = genElement;
			untyped genElement.__data = data;
			data.thumbnailStringCache = null;
			data.iconStringCache = null;

			genElement.innerHTML = '
				<fancy-thumbnail></fancy-thumbnail>
				<fancy-name></fancy-name>
				<div class="icon-placement"></div>
			';

			if (!tooltip) {
				genElement.ondblclick = (e) -> {
					onDoubleClick(data.item);
				}

				genElement.onclick = dataClickHandler.bind(data);

				genElement.oncontextmenu = contextMenuHandler.bind(data.item);

				genElement.onmouseover = (e: js.html.MouseEvent) -> {
					var child = getElement(data, true);
					this.tooltip.element.empty();
					this.tooltip.element.append(child);
				}

				setupDragAndDrop(data);
			}
		}

		var details = this.details;
		var itemWidthPx = this.itemWidthPx;
		var itemHeightPx = this.itemHeightPx;
		if (tooltip) {
			itemWidthPx = zoomedThumbnailSize;
			itemHeightPx = zoomedThumbnailSize + itemTitleHeight;
			details = false;
		}

		if (!details) {
			genElement.style.width = '${itemWidthPx}px';
			genElement.style.height = '${itemHeightPx}px';
		} else {
			genElement.style.width = '100%';
		}

		genElement.style.height = '${itemHeightPx}px';

		if (!tooltip) {
			genElement.classList.toggle("details", details);
			genElement.classList.toggle("selected", selection.exists(cast data));
			genElement.classList.toggle("current", currentVisible && currentItem == data);
		}

		var name = genElement.querySelector("fancy-name");
		var ranges = getItemRanges(data.item);
		if (name.title != data.name || data.ranges != ranges) {
			data.ranges = ranges;
			if (data.ranges != null) {
				name.innerHTML = FancySearch.splitSearchRanges(data.name, data.ranges);
			} else {
				name.innerHTML = data.name;
			}
			name.title = data.name;
		}

		var img = genElement.querySelector("fancy-thumbnail");
		var imgString = getThumbnail(data.item) ?? '<fancy-image style="background-image:url(\'res/icons/svg/unknown_file.svg\')"></fancy-image>';
		if (imgString != data.thumbnailStringCache) {
			img.innerHTML = imgString;
			data.thumbnailStringCache = imgString;
		}

		var icon = genElement.querySelector(".icon-placement");
		var iconString = getIcon(data.item);
		if (iconString != data.iconStringCache) {
			icon.innerHTML = iconString;
			data.iconStringCache = iconString;
		}

		return genElement;
	}

	function rebuildItems() {
		currentData.resize(0);
		var items = getItems();
		for (item in items) {
			var data = hrt.tools.MapUtils.getOrPut(itemMap, cast item, {
				item: item,
				name: getName(item),
				element: null,
				thumbnailStringCache: null,
				iconStringCache: null,
				ranges: null,
			});

			currentData.push(data);
		}
	}

	function inputHandler(event: js.html.KeyboardEvent) {
		if (onKeyPress(event)) {
			event.stopPropagation();
			event.preventDefault();
		}
	}
}