package hide.comp;

enum GalleryRefreshFlag {
	Search;
	Items;
	RegenHeader;
}

typedef GalleryRefreshFlags = haxe.EnumFlags<GalleryRefreshFlag>;

typedef GalleryItemData<GalleryItem> = {item: GalleryItem, name: String, element: js.html.Element, thumbnailStringCache: String, iconStringCache: String};

class FancyGallery<GalleryItem> extends hide.comp.Component {

	var currentData : Array<GalleryItemData<GalleryItem>> = [];
	var itemMap : Map<{}, GalleryItemData<GalleryItem>> = [];
	var itemContainer : js.html.Element;
	var scroll : js.html.Element;

	var lastHeight : Float = 0;

	var itemHeightPx = 128;
	var itemWidthPx = 128;
	static final itemTitleHeight = 32;

	var details = false;

	public function new(parent: Element, el: Element) {
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
					if (details) {
						itemWidthPx = 32;
						details = false;
					} else {
						itemWidthPx = hxd.Math.floor(itemWidthPx * 1.25);
					}
				} else if (e.deltaY > 0) {
					itemWidthPx = hxd.Math.floor(itemWidthPx / 1.25);
				}

				if (itemWidthPx < 32) {
					details = true;
				}
				queueRefresh();
			}
		}

		itemContainer.oncontextmenu = contextMenuHandler.bind(null);
		scroll = el.find("fancy-scroll").get(0);

		scroll.onscroll = (e) -> queueRefresh();
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

	/**
		Never call this directly
	**/
	function onRefreshInternal() {
		refreshQueued = false;

		if (currentRefreshFlags.has(Items)) {
			rebuildItems();
		}

		var oldChildren = [for (node in itemContainer.childNodes) node];

		var margin = 8;

		var bounds = scroll.getBoundingClientRect();


		if (details) {
			margin = 0;
			itemHeightPx = 16;
			itemWidthPx = hxd.Math.floor(bounds.width);
		} else {
			itemHeightPx = itemWidthPx + itemTitleHeight;
		}


		var numData = currentData.length;


		var itemsPerRow = hxd.Math.imax(hxd.Math.floor((bounds.width - margin) / (itemWidthPx + margin)), 1);

		var height = hxd.Math.ceil(numData / itemsPerRow) * (itemHeightPx + margin) + margin;
		if (height != lastHeight) {
			itemContainer.style.height = '${height}px';
			lastHeight = height;
		}

		// We might need to recompute the scroll height so we call getBoundingClientRect again
		var scrollHeight = scroll.getBoundingClientRect().height;



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
			if (dragAndDropInterface.onDragStart(data.item, e.dataTransfer)) {
				e.dataTransfer.effectAllowed = "move";
				e.dataTransfer.setDragImage(data.element, 0,0);
			} else {
				e.preventDefault();
			}
		}
	}

	function getElement(data : GalleryItemData<GalleryItem>) : js.html.Element {
		if (currentRefreshFlags.has(RegenHeader) && data.element != null) {
			data.element.remove();
			data.element = null;
		}

		if (data.element == null) {
			data.element = js.Browser.document.createElement("fancy-item");
			untyped data.element.__data = data;
			data.thumbnailStringCache = null;
			data.iconStringCache = null;

			data.element.innerHTML = '
				<fancy-thumbnail></fancy-thumbnail>
				<fancy-name></fancy-name>
				<div class="icon-placement"></div>
			';

			data.element.ondblclick = (e) -> {
				onDoubleClick(data.item);
			}

			data.element.oncontextmenu = contextMenuHandler.bind(data.item);

			setupDragAndDrop(data);
		}

		if (!details) {
			data.element.style.width = '${itemWidthPx}px';
			data.element.style.height = '${itemHeightPx}px';
		} else {
			data.element.style.width = '100%';
		}

		data.element.style.height = '${itemHeightPx}px';
		data.element.classList.toggle("details", details);

		var name = data.element.querySelector("fancy-name");
		if (name.title != data.name) {
			name.innerHTML = '<span class="bg">${data.name}</span>';
			name.title = data.name;
		}

		var img = data.element.querySelector("fancy-thumbnail");
		var imgString = getThumbnail(data.item) ?? '<fancy-image style="background-image:url(\'res/icons/svg/unknown_file.svg\')"></fancy-image>';
		if (imgString != data.thumbnailStringCache) {
			img.innerHTML = imgString;
			data.thumbnailStringCache = imgString;
		}

		var icon = data.element.querySelector(".icon-placement");
		var iconString = getIcon(data.item);
		if (iconString != data.iconStringCache) {
			icon.innerHTML = iconString;
			data.iconStringCache = iconString;
		}

		return data.element;
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
			});

			currentData.push(data);
		}
	}
}