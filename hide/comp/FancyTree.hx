package hide.comp;

/**
	TODO :
		[X] Selection
		[X] Current Item
		[X] Arrow navigation
		[X] Search
		[ ] Rename item
		[ ] Move items
		[ ] Save fold state
		[ ] Customisable context menu
		[ ] Customisable end of list icons
		[ ] Custom "pills" info near the title
		[X] General styling

**/

enum MoveAllowedOperations {
	Reorder;
	Reparent;
}

typedef MoveFlags = haxe.EnumFlags<MoveAllowedOperations>;

enum RefreshFlag {
	Flat;
	Search;
	FocusCurrent;
	RegenHeader;
}

typedef RefreshFlags = haxe.EnumFlags<RefreshFlag>;

enum FilterFlag {
	Visible;
	MatchSearch;
	Open;
}

typedef FilterFlags = haxe.EnumFlags<FilterFlag>;

typedef TreeItemData<TreeItem> = {element: js.html.Element, ?searchRanges: SearchRanges, item: TreeItem, name: String, ?iconCache: String, open: Bool, filterState: FilterFlags, children: Array<TreeItemData<TreeItem>>, parent: TreeItemData<TreeItem>, depth: Int, identifier: String};

enum abstract GetDragTarget(Int) {
	var None;
	var Top;
	var Bot;
	var In;
}


typedef SearchRanges = Array<Int>;
class FancyTree<TreeItem> extends hide.comp.Component {
	var rootData : Array<TreeItemData<TreeItem>> = [];
	var itemMap : Map<{}, TreeItemData<TreeItem>> = [];
	var selection : Map<{}, Bool> = [];
	var openState: Map<String, Bool> = [];
	var currentItem(default, set) : TreeItemData<TreeItem>;
	var currentVisible(default, set) : Bool = false;

	public var moveFlags(default, set) : MoveFlags = MoveFlags.ofInt(0);
	function set_moveFlags(v) {
		moveFlags = v;
		queueRefresh(RegenHeader); // We need to regen the header to bind the various drag & drop events
		return moveFlags;
	}

	function set_currentVisible(v) {
		currentVisible = v;
		if (currentVisible)
			queueRefresh(FocusCurrent);
		else
			queueRefresh(cast 0);
		return currentVisible;
	}

	function set_currentItem(v) {
		currentItem = v;
		queueRefresh(FocusCurrent);
		return currentItem;
	}

	var searchBar : hide.comp.FancySearch = null;

	var flatData : Array<TreeItemData<TreeItem>>;

	var itemContainer : js.html.Element;
	var scroll : js.html.Element;
	var currentSearch : String = "";

	var moveLastDragOver: TreeItemData<TreeItem>;

	public function new(parent: Element) {
		var el = new Element('<fancy-tree2 tabindex="-1">
				<fancy-search></fancy-search>
				<fancy-scroll>
				<fancy-item-container>
				</fancy-item-container>
				</fancy-scroll>
			</fancy-tree2>'
		);
		super(parent, el);

		searchBar = new FancySearch(null, element.find("fancy-search"));
		searchBar.onSearch = (search, _) -> {
			currentSearch = search.toLowerCase();
			queueRefresh(Flat | Search);
		}

		scroll = el.find("fancy-scroll").get(0);
		itemContainer = el.find("fancy-item-container").get(0);
		lastHeight = null;

		var fancyTree = el.get(0);
		fancyTree.onkeydown = inputHandler;

		scroll.onscroll = (e) -> queueRefresh(cast 0);

		fancyTree.onblur = (e) -> {
			currentVisible = false;
			currentItem = null;
		}

		fancyTree.onclick = (e) -> {
			currentVisible = false;
		}
 	}


	/**
		To customise the icon of an element
	**/
	public dynamic function getIcon(item: TreeItem) : String {return null;}

	/**
		The display name of an item
	**/
	public dynamic function getName(item: TreeItem) : String {return "undefined";}

	/**
		If items in the tree can have the same name, this function should return a unique name for each of them.
		Used to save the state of the open folders in the tree
	**/
	public dynamic function getUniqueName(item: TreeItem) : String {return getName(item);}

	/**
		Called when the selected items in the tree changed
	**/
	public dynamic function onSelectionChanged() {
	}

	/**
		Used to filter if an item can be reparented to another. Only called if MoveFlags contains Reparent.
		If this function return false, the reparent operation between the two arguments is not allowed
	**/
	public dynamic function canReparentTo(items: Array<TreeItem>, newParent: TreeItem) : Bool {
		return true;
	}

	/**
		Called to handle a reparent/reorder operation. newIndex will be -1 if the current MoveFlags don't contain can reorder, and t
	**/
	public dynamic function onMove(items: Array<TreeItem>, newParent: TreeItem, newIndex: Int) : Void {
	}

	// /**
	// 	Called when the user tries to drag an item from the tree. You can use the current selection
	// 	to move more than one item at once.
	// 	Return false to cancel the drag operation
	// **/
	// public dynamic function setupDrag(item: TreeItem, dataTransfer: js.html.DataTransfer) : Bool {
	// 	return false;
	// }

	// /**
	// 	Return true if the data in dataTransfer can be dropped on the given item
	// **/
	// public dynamic function canReciveDrop(parent: TreeItem, dataTransfer: js.html.DataTransfer) : ReciveDropKind {
	// 	return false;
	// }

	// /**
	// 	Handle the drop operation
	// **/
	// public dynamic function doDrop(parent: TreeItem, dataTransfer: js.html.DataTransfer) : Void {

	// }

	/**
		Called when the user renamed the item via F2 / Context menu
	**/
	public dynamic function onNameChange(item: TreeItem, newName: String) : Void {
	}

	/**
		Called for each of your items in the tree. for the root elements, get called with null as a parameter
	**/
	public dynamic function getChildren(item: TreeItem) : Array<TreeItem> {return null;}

	/**
		Returns a string that allow an item in the tree to be uniquely identified.
		Default to a path/of/the/item/name
		Customize this if you have items that can share names
	**/
	public dynamic function getIdentifier(item: TreeItem) : String {
		var data = itemMap.get(cast item);
		if (data == null)
			return null;
		function rec(data) {
			if (data.parent != null)
				return getIdentifier(data.parent) + "/" + data.name;
			return data.name;
		}

		return rec(data);
	}

	/**
		Called to know if an item in the tree can be opened or has children. Default to calling getChildren and seeing if it returns false.
		Set this function to optimise the initial loading of the tree if getChildren is expensive
	**/
	public dynamic function hasChildren(item : TreeItem) : Bool {
		var children = getChildren(item);
		if (children == null)
			return false;
		return children.length > 0;
	}

	public function getSelectedItems() : Array<TreeItem> {
		return [for (item => _ in selection) cast item];
	}

	public function generateChildren(parentData: TreeItemData<TreeItem>) : Array<TreeItemData<TreeItem>> {
		var childrenTreeItem = getChildren(parentData?.item);

		var childrenData : Array<TreeItemData<TreeItem>> = [];
		if (childrenTreeItem != null) {
			for (childItem in childrenTreeItem) {
				var childData : TreeItemData<TreeItem>;
				childData = {
					item: childItem,
					parent: parentData,
					children: null,
					open: false,
					filterState: Visible,
					depth: parentData?.depth + 1 ?? 0,
					element: null,
					name: StringTools.htmlEscape(getName(childItem)),
					identifier: getIdentifier(childItem),
				};
				itemMap.set(cast childItem, childData);
				childrenData.push(childData);
			}
		}
		if (parentData != null) {
			parentData.children = childrenData;
		}
		return childrenData;
	}

	/**
		The type used by this tree in the drag/drop operations
	**/
	inline public function getDragDataType() {
		return ("application/x." + saveDisplayKey + ".move").toLowerCase();
	}

	public function ensureVisible(data) {

	}

	public function rebuildTree() {
		rootData = generateChildren(null);

		queueRefresh(Flat | Search);
	}

	function regenerateFlatData() {
		flatData = [];
		flattenRec(rootData, flatData);
	}

	function inputHandler(e: js.html.KeyboardEvent) {
		if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
			e.stopPropagation();
			e.preventDefault();

			searchBar.toggleSearch(true, true);
		}

		// if (hide.ui.Keys.matchJsEvent("rename", e, ide.currentConfig) && selection.iterator().hasNext()) {
		// 	e.stopPropagation();
		// 	e.preventDefault();

		// 	beginRename(cast selection.keyValueIterator().next().key);
		// }

		if (e.key == "Escape") {
			if (searchBar.isOpen()) {
				e.stopPropagation();
				e.preventDefault();

				searchBar.toggleSearch(false);
				element.get(0).focus();
				currentSearch = "";
				queueRefresh(Search);
			}
		}

		var delta = 0;
		switch (e.key) {
			case "ArrowUp":
				delta -= 1;
			case "ArrowDown":
				delta += 1;
			case "PageUp":
				delta -= 10;
			case "PageDown":
				delta += 10;
		}

		if (delta != 0) {
			e.stopPropagation();
			e.preventDefault();
			moveCurrent(delta);
			return;
		}

		if (currentItem == null)
			return;

		if (e.key == "ArrowRight" && hasChildren(currentItem.item)) {
			e.stopPropagation();
			e.preventDefault();

			if (currentItem == null || isOpen(currentItem)) {
				moveCurrent(1);
			}
			else if (currentItem != null && !isOpen(currentItem)) {
				toggleDataOpen(currentItem, true);
				//saveState();
			}
			return;
		}
		if (e.key == "ArrowLeft") {
			e.stopPropagation();
			e.preventDefault();

			var anyChildren = hasChildren(currentItem.item);
			var goToParent = !anyChildren && currentItem.parent != null;
			goToParent = goToParent || anyChildren && !isOpen(currentItem);

			if (goToParent && currentItem.parent != null) {
				currentItem = currentItem.parent;
			} else if(anyChildren && currentItem != null) {
				toggleDataOpen(currentItem, false);
				//saveState();
			}
			return;
		}

		if (e.key == "Enter") {
			e.stopPropagation();
			e.preventDefault();

			clearSelection();
			if (currentItem != null) {
				setSelection(currentItem, true);
			}
			onSelectionChanged();
			return;
		}
	}

	public function moveCurrent(delta: Int) {
		if (delta == 0)
			return;
		if (flatData.length <= 0)
			return;

		currentVisible = true;

		var currentIndex = flatData.indexOf(currentItem);
		if (currentIndex < 0) {
			currentItem = flatData[0];

			if (searchBar.isOpen() && searchBar.hasFocus()) {
				searchBar.blur();
				element.focus();
			}
			return;
		}

		var nextIndex = currentIndex + delta;
		if (nextIndex < 0) {
			if (searchBar.isOpen()) {
				searchBar.focus();
				return;
			}
			else {
				nextIndex = 0;
			}
		}
		else {
			if (searchBar.isOpen() && searchBar.hasFocus()) {
				searchBar.blur();
				element.focus();
			}
		}

		if (nextIndex > flatData.length-1)
			nextIndex = flatData.length-1;

		if (nextIndex != currentIndex) {
			currentItem = flatData[nextIndex];
		}
	}

	var lastHeight = null;

	// Never call this function directly, instead call queueRefresh();
	function onRefreshInternal() {
		if (currentRefreshFlags.has(Search)) {
			filterRec(rootData);
			currentRefreshFlags.set(Flat);
		}

		if (currentRefreshFlags.has(Flat) || flatData == null) {
			regenerateFlatData();
		}

		//itemContainer.innerHTML = "";
		var oldChildren = [for (node in itemContainer.childNodes) node];

		var itemHeightPx = 20;

		var height = itemHeightPx * flatData.length;
		if (height != lastHeight) {
			itemContainer.style.height = '${height}px';
			lastHeight = height;
		}

		var scrollHeight = scroll.getBoundingClientRect().height;

		if (currentRefreshFlags.has(FocusCurrent)) {
			var currentIndex = flatData.indexOf(currentItem);

			if (currentIndex >= 0) {
				var currentHeight = currentIndex * itemHeightPx;
				if (currentHeight < scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight);
				}

				if (currentHeight + itemHeightPx - scrollHeight > scroll.scrollTop) {
					scroll.scrollTo(scroll.scrollLeft, currentHeight + itemHeightPx - scrollHeight);
				}
			}
		}

		var clipStart = scroll.scrollTop;
		var clipEnd = scrollHeight + clipStart;
		var itemStart = hxd.Math.floor(clipStart / itemHeightPx);
		var itemEnd = hxd.Math.ceil(clipEnd / itemHeightPx);

		for (index in hxd.Math.imax(itemStart, 0) ... hxd.Math.imin(flatData.length, itemEnd + 1)) {
			var data = flatData[index];
			var element = genElement(data);
			element.style.top = '${index * itemHeightPx}px';
			if (!oldChildren.remove(element))
				itemContainer.appendChild(element);
		}

		for (oldChild in oldChildren) {
			itemContainer.removeChild(oldChild);
		}

		currentRefreshFlags = RefreshFlags.ofInt(0);
		refreshQueued = false;
	}

	static function computeSearchRanges(haystack: String, needle: String) : SearchRanges {
		var pos = haystack.toLowerCase().indexOf(needle);
		if (pos < 0)
			return null;
		return [pos, pos + needle.length];
	}

	public function filterRec(children: Array<TreeItemData<TreeItem>>) : Bool {
		var anyVisible = false;
		for (child in children) {
			child.filterState = FilterFlags.ofInt(0);
			child.searchRanges = null;

			if (currentSearch.length == 0) {
				child.filterState |= Visible;
			} else {
				child.searchRanges = computeSearchRanges(child.name, currentSearch);
				if (child.searchRanges != null) {
					child.filterState |= MatchSearch;
					child.filterState |= Visible;
				}
			}
			if (child.children == null) {
				generateChildren(child);
			}

			if(filterRec(child.children) && currentSearch.length > 0) {
				child.filterState |= Visible;
				child.filterState |= Open;
			}

			anyVisible = anyVisible || child.filterState.has(Visible);
		}

		return anyVisible;
	}

	function genElement(data: TreeItemData<TreeItem>) : js.html.Element {
		var element : js.html.Element = data.element;

		if (currentRefreshFlags.has(RegenHeader) && data.element != null) {
			data.element.remove();
			data.element = null;
		}

		if (data.element == null) {
			element = js.Browser.document.createElement("fancy-tree-item");
			element.style.setProperty("--depth", Std.string(data.depth));

			element.innerHTML =
			'
				<fancy-tree-icon class="caret"></fancy-tree-icon>
				<fancy-tree-icon class="header-icon"></fancy-tree-icon>
				<fancy-tree-name></fancy-tree-name>
			';

			var fold = element.querySelector(".caret");
			fold.addEventListener("click", (e) -> {
				toggleDataOpen(data);
				//saveState();
			});

			var closure = dataClickHandler.bind(data);

			var icon = element.querySelector(".header-icon");
			icon.onclick = closure;

			var name = element.querySelector("fancy-tree-name");
			name.onclick = closure;

			data.element = element;

			setupDragAndDrop(data);
		}

		var fold = element.querySelector(".caret");
		fold.classList.toggle("hidden", !hasChildren(data.item));
		element.classList.toggle("open", isOpen(data));
		element.classList.toggle("selected", selection.exists(cast data));
		element.classList.toggle("current", currentVisible && currentItem == data);

		var icon = element.querySelector(".header-icon");
		var iconContent = getIcon(data.item);
		icon.classList.toggle("hidden", iconContent == null);
		if (iconContent != null && iconContent != data.iconCache) {
			icon.innerHTML = iconContent;
			data.iconCache = iconContent;
		}

		var nameElement = element.querySelector("fancy-tree-name");
		element.title = data.name;

		if (data.searchRanges != null) {
			var name = data.name;
			var lastPos = 0;
			var finalName = "";
			for (index in 0...(data.searchRanges.length>>1)) {
				var first = name.substr(lastPos, data.searchRanges[index]);
				var match = name.substr(data.searchRanges[index], data.searchRanges[index+1] - data.searchRanges[index]);
				finalName += first + '<span class="search-hl">' + match + "</span>";
				lastPos = data.searchRanges[index+1];
			}
			finalName += name.substr(lastPos);
			nameElement.innerHTML = finalName;
		} else {
			nameElement.innerHTML = data.name;
		}

		return data.element;
	}

	function setupDragAndDrop(data: TreeItemData<TreeItem>) {
		// if (moveFlags.toInt() != 0) {
		// 	data.element.draggable = true;

		// 	data.element.ondragstart = (e: js.html.DragEvent) -> {
		// 		if (!selection.get(cast data)) {
		// 			clearSelection();
		// 			setSelection(data, true);
		// 		}

		// 		moveLastDragOver = null;

		// 		if (setupDrag(data, e.dataTransfer)) {
		// 			e.dataTransfer.effectAllowed = "move";
		// 			e.dataTransfer.setDragImage(data.element, 0, 0);
		// 		}
		// 		e.preventDefault();
		// 	}

		// 	data.element.ondragover = (e: js.html.DragEvent) -> {
		// 		if (canHandleDrop(data, e.dataTransfer)) {
		// 			var target = getDragTarget(data,e);

		// 			if (canPreformMove(data, target) == null)
		// 				return;

		// 			if (target == In) {
		// 				if (moveLastDragOver == data.item) {
		// 					moveLastDragTime += 1;
		// 				}
		// 				else {
		// 					moveLastDragOver = data.item;
		// 					moveLastDragTime = 0;
		// 				}

		// 				if (moveLastDragTime > 25 && !isDataVisuallyOpen(data)) {
		// 					toggleItemOpen(data.item, true, true, false);
		// 					saveState();
		// 				}
		// 			}

		// 			setDragStyle(data.element, target);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.element.ondragenter = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			var target = getDragTarget(data,e);
		// 			if (canPreformMove(data, target) == null)
		// 				return;
		// 			setDragStyle(data.element, target);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.element.ondragleave = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			setDragStyle(data.element, None);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.element.ondragexit = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			setDragStyle(data.element, None);
		// 			e.preventDefault();
		// 		}
		// 	}

		// 	data.element.ondrop = (e: js.html.DragEvent) -> {
		// 		if (e.dataTransfer.types.contains(getDragDataType())) {
		// 			var target = getDragTarget(data,e);
		// 			var moveOp = canPreformMove(data, target);

		// 			setDragStyle(data.element, None);
		// 			e.preventDefault();

		// 			if (moveOp == null)
		// 				return;

		// 			onMove(moveOp.toMove, moveOp.newParent, moveOp.newIndex);
		// 		}
		// 	}
		// }
	}

	function setDragStyle(element: js.html.Element, target: GetDragTarget) {
		trace(target);
		element.classList.toggle("feedback-drop-top", target == Top);
		element.classList.toggle("feedback-drop-bot", target == Bot);
		element.classList.toggle("feedback-drop-in", target == In);
	}

	function getDragTarget(data: TreeItemData<TreeItem>, event: js.html.DragEvent) : GetDragTarget {
		var element = data.element;
		// var canDropIn = moveFlags.has(Reparent) && canReparentTo()
		if (!moveFlags.has(Reorder)) {
			return In;
		}

		var rect = element.getBoundingClientRect();
		var name = element.querySelector("fancy-tree-name");
		var nameRect = element.getBoundingClientRect();

		var padding = js.Browser.window.getComputedStyle(element).getPropertyValue;
		if (moveFlags.has(Reparent) && event.clientX > nameRect.left + 100) {
			return In;
		}

		if (event.clientY > rect.top + rect.height / 2) {
			return Bot;
		}
		return Top;
	}

	public function clearSelection() {
		selection.clear();
		queueRefresh(cast 0);
	}



	function setSelection(data: TreeItemData<TreeItem>, select: Bool) {
		if (select) {
			selection.set(cast data, true);
		} else {
			selection.remove(cast data);
		}
	}

	function dataClickHandler(data: TreeItemData<TreeItem>, event: js.html.MouseEvent) : Void {
		if (!event.ctrlKey) {
			clearSelection();
		}

		var currentIndex = flatData.indexOf(data);
		if (event.shiftKey && currentIndex >= 0) {

		}

		var currentIndex = flatData.indexOf(currentItem);
		if (event.shiftKey && currentIndex >= 0) {
			var newIndex = flatData.indexOf(data);

			var min = hxd.Math.imin(currentIndex, newIndex);
			var max = hxd.Math.imax(currentIndex, newIndex);

			for (i in min...max + 1) {
				setSelection(flatData[i], true);
			}
		} else {
			setSelection(data, !selection.exists(cast data));
		}

		if (!(event.shiftKey && !event.ctrlKey) || currentItem == null)
			currentItem = data;
		onSelectionChanged();

		queueRefresh(cast 0);
	}

	function toggleDataOpen(data: TreeItemData<TreeItem>, ?force: Bool) {
		var want = force ?? !isOpen(data);
		if (currentSearch.length > 0) {
			data.filterState.setTo(Open, want);
		}
		data.open = want;
		queueRefresh(Flat);
	}

	var refreshQueued : Bool = false;
	var currentRefreshFlags : RefreshFlags = RefreshFlags.ofInt(0);

	function queueRefresh(flags: RefreshFlags) {
		currentRefreshFlags |= flags;
		if (!refreshQueued) {
			refreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onRefreshInternal());
		}
	}

	public static function animateReveal(element: js.html.Element, reveal: Bool, durationMs: Int = 75) {
		function finish() {
			if (reveal) {
				element.style.height = "auto";
			} else {
				element.style.height = null;
			}
		};
		for (anim in element.getAnimations()) {
			anim.cancel();
		}

		if (durationMs > 0) {
			var anim = element.animate([
				{height: "0px"},
				{height: '${element.scrollHeight}px'},
			], {
				duration: durationMs,
				iterations: 1,
				direction: reveal ? js.html.PlaybackDirection.NORMAL : js.html.PlaybackDirection.REVERSE,
				easing: "ease-in",
			});

			anim.onfinish = (e) -> finish();
		}
		else {
			finish();
		}
	}
	function flattenRec(currentArray: Array<TreeItemData<TreeItem>>, targetArray: Array<TreeItemData<TreeItem>>) {
		for (child in currentArray) {
			if (!child.filterState.has(Visible)) continue;
			targetArray.push(child);
			if (isOpen(child)) {
				if (child.children == null)
					generateChildren(child);
				flattenRec(child.children, targetArray);
			}
		}
	}

	function isOpen(data: TreeItemData<TreeItem>) {
		return data.open || data.filterState.has(Open);
	}


}