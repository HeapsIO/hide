// package hide.comp;

// /**
// 	TODO :
// 		[X] Search
// 		[X] Rename item
// 		[ ] Move items
// 		[X] Save fold state
// 		[ ] Customisable context menu
// 		[ ] Customisable end of list icons
// 		[ ] Custom "pills" info near the title
// 		[X] Fold animation
// 		[X] General styling

// **/

// enum MoveAllowedOperations {
// 	Reorder;
// 	Reparent;
// }

// typedef MoveFlags = haxe.EnumFlags<MoveAllowedOperations>;

// enum GetDragTarget {
// 	None;
// 	Top;
// 	Bot;
// 	In;
// }


// typedef TreeItemData<TreeItem> = {?element: js.html.Element, ?header: js.html.Element, ?children: Array<TreeItem>, ?parent: TreeItem, ?depth: Int, ?item: TreeItem, ?temporaryOpen: Bool, ?passSearch: Bool, ?name: String, ?path: String};

// class FancyTree<TreeItem : Dynamic> extends hide.comp.Component {
// 	public var itemMap : Map<{}, TreeItemData<TreeItem>> = [];

// 	// Forced to use another object because itemMap can't use null as an index for some reason
// 	var rootData : TreeItemData<TreeItem> = {};

// 	var openState: Map<String, Bool> = [];

// 	public var moveFlags : MoveFlags = MoveFlags.ofInt(0);

// 	var selection : Map<{}, Bool> = [];
// 	var currentItem : TreeItem;

// 	var searchBar : hide.comp.FancySearch = null;

// 	var moveLastDragOver : TreeItem;
// 	var moveLastDragTime : Int = 0;

// 	public function new(parent: Element) {
// 		var el = new Element('<fancy-tree tabindex="-1">
// 			<fancy-search></fancy-search>
// 			<fancy-wrapper></fancy-wrapper></fancy-tree>');
// 		super(parent, el);

// 		searchBar = new FancySearch(null, element.find("fancy-search"));
// 		searchBar.onSearch = (search, _) -> {
// 			filterRec(null, search);

// 			ensureVisible(getDataOrRoot(currentItem));
// 		}

// 		var fancyTree = el.get(0);
// 		fancyTree.onkeydown = (e: js.html.KeyboardEvent) -> {

// 			if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
// 				e.stopPropagation();
// 				e.preventDefault();

// 				searchBar.toggleSearch(true, true);
// 			}

// 			if (hide.ui.Keys.matchJsEvent("rename", e, ide.currentConfig) && selection.iterator().hasNext()) {
// 				e.stopPropagation();
// 				e.preventDefault();

// 				beginRename(cast selection.keyValueIterator().next().key);
// 			}

// 			if (e.key == "Escape") {
// 				if (searchBar.isOpen()) {
// 					e.stopPropagation();
// 					e.preventDefault();

// 					searchBar.toggleSearch(false);
// 					fancyTree.focus();
// 					resetSearch(null);
// 				}
// 			}

// 			var delta = 0;
// 			switch (e.key) {
// 				case "ArrowUp":
// 					delta -= 1;
// 				case "ArrowDown":
// 					delta += 1;
// 				case "PageUp":
// 					delta -= 10;
// 				case "PageDown":
// 					delta += 10;
// 			}

// 			if (delta != 0) {
// 				e.stopPropagation();
// 				e.preventDefault();
// 				moveCurrent(delta);
// 				return;
// 			}

// 			if (currentItem == null)
// 				return;

// 			if (e.key == "ArrowRight" && hasChildren(currentItem)) {
// 				e.stopPropagation();
// 				e.preventDefault();

// 				var currentData = getDataOrRoot(currentItem);
// 				if (currentData == null || isDataVisuallyOpen(currentData)) {
// 					moveCurrent(1);
// 				}
// 				else if (currentData != null && !isDataVisuallyOpen(currentData)) {
// 					toggleItemOpen(currentItem, true);
// 					saveState();
// 				}
// 				return;
// 			}
// 			if (e.key == "ArrowLeft") {
// 				e.stopPropagation();
// 				e.preventDefault();

// 				var currentData = getDataOrRoot(currentItem);
// 				if (currentData != null) {
// 					var anyChildren = hasChildren(currentItem);
// 					var goToParent = !anyChildren && currentData.parent != null;
// 					goToParent = goToParent || anyChildren && !isDataVisuallyOpen(currentData);

// 					if (goToParent && currentData.parent != null) {
// 						setCurrent(currentData.parent);
// 					} else if(anyChildren && currentItem != null) {
// 						toggleItemOpen(currentItem, false);
// 						saveState();
// 					}
// 				}
// 				return;
// 			}

// 			if (e.key == "Enter") {
// 				e.stopPropagation();
// 				e.preventDefault();

// 				clearSelection();
// 				if (currentItem != null) {
// 					setSelection(currentItem, true);
// 				}
// 				onSelectionChanged();
// 				return;
// 			}
// 		};

// 		resetItemCache();
// 	}

// 	public function beginRename(item: TreeItem) {
// 		var data = getDataOrRoot(item);

// 		var name = data.header.querySelector("fancy-tree-name");
// 		name.contentEditable = "plaintext-only";
// 		var edit = new ContentEditable(null, new Element(name));

// 		edit.onChange = (newValue) -> {
// 			onNameChange(item, name.textContent);
// 			refreshHeader(data);
// 			element.focus();
// 		}

// 		edit.onCancel = () -> {
// 			refreshHeader(data);
// 			element.focus();
// 		}

// 		edit.element.focus();
// 	}

// 	function saveState() {
// 		saveDisplayState("openState", openState);
// 	}

// 	inline function isDataVisuallyOpen(data: TreeItemData<TreeItem>) {
// 		return data.item == null || openState.get(data.path) || data.temporaryOpen;
// 	}

// 	/**
// 		Called for each of your items in the tree. for the root elements, get called with null as a parameter
// 	**/
// 	public dynamic function getChildren(item: TreeItem) : Array<TreeItem> {return null;}

// 	/**
// 		Called to know if an item in the tree can be opened or has children. Default to calling getChildren and seeing if it returns false.
// 		Set this function to optimise the initial loading of the tree if getChildren is expensive
// 	**/
// 	public dynamic function hasChildren(item : TreeItem) : Bool {
// 		var children = getChildren(item);
// 		if (children == null)
// 			return false;
// 		return children.length > 0;
// 	}

// 	/**
// 		To customise the icon of an element
// 	**/
// 	public dynamic function getIcon(item: TreeItem) : js.html.Element {return null;}

// 	/**
// 		The display name of an item
// 	**/
// 	public dynamic function getName(item: TreeItem) : String {return "undefined";}

// 	/**
// 		If items in the tree can have the same name, this function should return a unique name for each of them.
// 		Used to save the state of the open folders in the tree
// 	**/
// 	public dynamic function getUniqueName(item: TreeItem) : String {return getName(item);}

// 	/**
// 		Called when the selected items in the tree changed
// 	**/
// 	public dynamic function onSelectionChanged() {
// 	}

// 	/**
// 		Used to filter if an item can be reparented to another. Only called if MoveFlags contains Reparent.
// 		If this function return false, the reparent operation between the two arguments is not allowed
// 	**/
// 	public dynamic function canReparentTo(items: Array<TreeItem>, newParent: TreeItem) : Bool {
// 		return true;
// 	}

// 	/**
// 		Called to handle a reparent/reorder operation. newIndex will be -1 if the current MoveFlags don't contain can reorder, and t
// 	**/
// 	public dynamic function onMove(items: Array<TreeItem>, newParent: TreeItem, newIndex: Int) : Void {
// 	}

// 	/**
// 		Called when the user renamed the item via F2 / Context menu
// 	**/
// 	public dynamic function onNameChange(item: TreeItem, newName: String) : Void {
// 	}

// 	public function getSelectedItems() : Array<TreeItem> {
// 		return [for (item => _ in selection) cast item];
// 	}

// 	/**
// 		Destroy and recreate all the elements in the tree.
// 		All the cached children will be erased
// 	**/
// 	public function rebuildTree() {
// 		resetItemCache();
// 		redrawItems();
// 		resetSearch(null);
// 	}

// 	function resetItemCache() {
// 		itemMap.clear();
// 		rootData = {element: js.Browser.document.createDivElement() /*element.find("fancy-wrapper").get(0)*/, depth: 0, path: ""};
// 		openState = getDisplayState("openState") ?? openState;
// 	}

// 	function redrawItems() {
// 		untyped rootData.element.replaceChildren();
// 		initChildren(null);
// 	}

// 	function toggleItemOpen(item: TreeItem, ?force: Bool, animate: Bool = true, temporary: Bool = false) : Void {

// 		var data = itemMap.get(cast item);

// 		var wantOpen = force ?? !isDataVisuallyOpen(data);
// 		var wasOpen = isDataVisuallyOpen(data);

// 		data.temporaryOpen = wantOpen;
// 		if (!temporary) {
// 			openState.set(data.path, wantOpen);
// 		}

// 		if (wantOpen) {
// 			initChildren(item);
// 		}

// 		data.element.classList.toggle("open", wantOpen);
// 		var childrenElement = data.element.querySelector("fancy-tree-children");
// 		if (animate && childrenElement != null && wantOpen != wasOpen) {
// 			animateReveal(childrenElement, wantOpen);
// 		}

// 	}

// 	public static function animateReveal(element: js.html.Element, reveal: Bool, durationMs: Int = 75) {
// 		function finish() {
// 			if (reveal) {
// 				element.style.height = "auto";
// 			} else {
// 				element.style.height = null;
// 			}
// 		};

// 		for (anim in element.getAnimations()) {
// 			anim.cancel();
// 		}

// 		if (durationMs > 0) {
// 			var anim = element.animate([
// 				{height: "0px"},
// 				{height: '${element.scrollHeight}px'},
// 			], {
// 				duration: durationMs,
// 				iterations: 1,
// 				direction: reveal ? js.html.PlaybackDirection.NORMAL : js.html.PlaybackDirection.REVERSE,
// 				easing: "ease-in",
// 			});

// 			anim.onfinish = (e) -> finish();
// 		}
// 		else {
// 			finish();
// 		}
// 	}

// 	function syncOpen(item: TreeItem) : Void {
// 		var data = getDataOrRoot(item);

// 		if (item != null)
// 			toggleItemOpen(item, openState.get(data.path) ?? false, false, false);

// 		if (data.children != null) {
// 			for (child in data.children) {
// 				syncOpen(child);
// 			}
// 		}
// 	}

// 	function resetSearch(item: TreeItem) : Void {
// 		var data = getDataOrRoot(item);
// 		data.passSearch = true;
// 		data.element.classList.toggle("hide-search", !data.passSearch);
// 		//initChildren(item);
// 		if (data.children != null) {
// 			for (child in data.children) {
// 				resetSearch(child);
// 			}
// 		}
// 		if (resetSearch == null)
// 			syncOpen(null);
// 	}

// 	static function filterMatch(haystack: String, needle: String) {
// 		return StringTools.contains(haystack.toLowerCase(), needle.toLowerCase());
// 	}

// 	/**
// 		Returns true if any children passes the current filter
// 	**/
// 	function filterRec(item: TreeItem, currentFilter: String) : Bool {
// 		if (item == null) {
// 			resetSearch(null);
// 		}
// 		var data = getDataOrRoot(item);

// 		data.passSearch = data.name != null ? filterMatch(data.name, currentFilter) : false;

// 		var anyChildrenPass = false;
// 		if (!data.passSearch) {
// 			if (data.children == null)
// 				initChildren(data.item);
// 			if (data.children != null) {
// 				for (child in data.children) {
// 					anyChildrenPass = filterRec(child, currentFilter) || anyChildrenPass;
// 				}
// 			}
// 		}

// 		if (anyChildrenPass) {
// 			data.passSearch = true;
// 			if (item != null) {
// 				toggleItemOpen(item, true, false, true);
// 			}
// 		}

// 		if (item != null) {
// 			data.element.classList.toggle("hide-search", !data.passSearch);
// 		}

// 		return data.passSearch;
// 	}

// 	function initChildren(item: TreeItem) : Void {
// 		var data = getDataOrRoot(item);
// 		if (data?.element == null || data?.depth == null)
// 			throw "Data is not properly initialised";

// 		if (data.children == null) {
// 			data.children = getChildren(item);

// 			if (data.children != null) {
// 				var childrenElement = js.Browser.document.createElement("fancy-tree-children");
// 				data.element.append(childrenElement);

// 				for (child in data.children) {
// 					if (child == null)
// 						continue;
// 					var childElem = getElement(child, item, data.depth + 1);
// 					if (childElem != null)
// 						childrenElement.append(childElem);
// 				}
// 			}
// 		}
// 	}

// 	function getDataOrRoot(item: TreeItem) {
// 		if (item != null) {
// 			return hrt.tools.MapUtils.getOrPut(itemMap, cast item, {item: item});
// 		} else {
// 			return rootData;
// 		}
// 	}

// 	/**
// 		The type used by this tree in the drag/drop operations
// 	**/
// 	inline public function getDragDataType() {
// 		return ("application/x." + saveDisplayKey + ".move").toLowerCase();
// 	}

// 	function refreshHeader(data: TreeItemData<TreeItem>) {
// 		data.header.innerHTML = "";

// 		var fold = js.Browser.document.createElement("fancy-tree-icon");
// 		data.header.append(fold);

// 		if (hasChildren(data.item)) {
// 			fold.classList.add("caret");
// 			fold.addEventListener("click", (e) -> {
// 				toggleItemOpen(data.item);
// 				saveState();
// 			});
// 		}

// 		function clickHandler(e: js.html.MouseEvent) {
// 			var lastSelected = currentItem;
// 			if (!e.ctrlKey) {
// 				clearSelection();
// 			}

// 			var flat = flattenTreeItems();
// 			var currentIndex = flat.indexOf(currentItem);
// 			if (e.shiftKey && currentIndex >= 0) {
// 				var currentIndex = flat.indexOf(currentItem);
// 				var newIndex = flat.indexOf(data.item);

// 				var min = hxd.Math.imin(currentIndex, newIndex);
// 				var max = hxd.Math.imax(currentIndex, newIndex);

// 				for (i in min...max + 1) {
// 					setSelection(flat[i], true);
// 				}
// 			} else {
// 				setSelection(data.item, !selection.exists(cast data.item));
// 			}

// 			if (!(e.shiftKey && !e.ctrlKey) || currentItem == null)
// 				setCurrent(data.item);
// 			onSelectionChanged();
// 		}

// 		var iconContent = getIcon(data.item);
// 		if (iconContent != null) {
// 			var icon = js.Browser.document.createElement("fancy-tree-icon");
// 			icon.append(iconContent);
// 			data.header.append(icon);
// 			icon.onclick = clickHandler;
// 		}

// 		var nameElement = js.Browser.document.createElement("fancy-tree-name");
// 		var name = getName(data.item) ?? "undefined";
// 		data.name = name;
// 		data.header.title = name;
// 		nameElement.innerText = name;
// 		data.header.append(nameElement);



// 		if (moveFlags.toInt() != 0) {
// 			data.header.draggable = true;

// 			data.header.ondragstart = (e: js.html.DragEvent) -> {
// 				var draggedPaths = [];
// 				moveLastDragOver = null;
// 				if (!selection.get(cast data.item)) {
// 					clearSelection();
// 					setSelection(data.item, true);
// 				}
// 				for (item in getSelectedItems()) {
// 					var data = getDataOrRoot(item);
// 					draggedPaths.push(data.path);
// 				}
// 				e.dataTransfer.setData(getDragDataType(), haxe.Json.stringify(draggedPaths));
// 				trace(e.dataTransfer.types);
// 				e.dataTransfer.effectAllowed = "move";
// 				e.dataTransfer.setDragImage(data.header, 0, 0);
// 			}

// 			data.header.ondragover = (e: js.html.DragEvent) -> {
// 				if (e.dataTransfer.types.contains(getDragDataType())) {
// 					var target = getDragTarget(data,e);

// 					if (canPreformMove(data, target) == null)
// 						return;

// 					if (target == In) {
// 						if (moveLastDragOver == data.item) {
// 							moveLastDragTime += 1;
// 						}
// 						else {
// 							moveLastDragOver = data.item;
// 							moveLastDragTime = 0;
// 						}

// 						if (moveLastDragTime > 25 && !isDataVisuallyOpen(data)) {
// 							toggleItemOpen(data.item, true, true, false);
// 							saveState();
// 						}
// 					}

// 					setDragStyle(data.header, target);
// 					e.preventDefault();
// 				}
// 			}

// 			data.header.ondragenter = (e: js.html.DragEvent) -> {
// 				if (e.dataTransfer.types.contains(getDragDataType())) {
// 					var target = getDragTarget(data,e);
// 					if (canPreformMove(data, target) == null)
// 						return;
// 					setDragStyle(data.header, target);
// 					e.preventDefault();
// 				}
// 			}

// 			data.header.ondragleave = (e: js.html.DragEvent) -> {
// 				if (e.dataTransfer.types.contains(getDragDataType())) {
// 					setDragStyle(data.header, None);
// 					e.preventDefault();
// 				}
// 			}

// 			data.header.ondragexit = (e: js.html.DragEvent) -> {
// 				if (e.dataTransfer.types.contains(getDragDataType())) {
// 					setDragStyle(data.header, None);
// 					e.preventDefault();
// 				}
// 			}

// 			data.header.ondrop = (e: js.html.DragEvent) -> {
// 				if (e.dataTransfer.types.contains(getDragDataType())) {
// 					var target = getDragTarget(data,e);
// 					var moveOp = canPreformMove(data, target);

// 					setDragStyle(data.header, None);
// 					e.preventDefault();

// 					if (moveOp == null)
// 						return;

// 					onMove(moveOp.toMove, moveOp.newParent, moveOp.newIndex);
// 				}
// 			}
// 		}
// 		nameElement.onclick = clickHandler;
// 	}

// 	function canPreformMove(data: TreeItemData<TreeItem>, target: GetDragTarget) : {toMove: Array<TreeItem>, newParent: TreeItem, newIndex: Int} {
// 		var toMove = getSelectedItems();

// 		var newParent = getDataOrRoot(data.parent);
// 		var newIndex = 0;
// 		var currIndex = newParent.children.indexOf(data.item);

// 		switch(target) {
// 			case Top:
// 				newIndex = currIndex;
// 			case Bot:
// 				newIndex = currIndex + 1;
// 			case In:
// 				newParent = data;
// 			default:
// 		}

// 		// Take into account that the item are removed from the children list before getting inserted at the new index,
// 		// which causes the index to not match if these items are before the target
// 		if (target == Top || target == Bot) {
// 			for (item in toMove) {
// 				var indexInParent = newParent.children.indexOf(item);
// 				if (indexInParent >= 0 && indexInParent < currIndex) {
// 					newIndex --;
// 				}
// 			}
// 		}

// 		if (!canReparentTo(toMove, newParent.item)) {
// 			return null;
// 		}

// 		return {toMove: toMove, newParent: newParent.item, newIndex: newIndex};
// 	}


// 	function setDragStyle(element: js.html.Element, target: GetDragTarget) {
// 		trace(target);
// 		element.classList.toggle("feedback-drop-top", target == Top);
// 		element.classList.toggle("feedback-drop-bot", target == Bot);
// 		element.classList.toggle("feedback-drop-in", target == In);
// 	}

// 	function getDragTarget(data: TreeItemData<TreeItem>, event: js.html.DragEvent) : GetDragTarget {
// 		var element = data.element;
// 		// var canDropIn = moveFlags.has(Reparent) && canReparentTo()
// 		if (!moveFlags.has(Reorder)) {
// 			return In;
// 		}

// 		var rect = element.getBoundingClientRect();
// 		var name = element.querySelector("fancy-tree-name");
// 		var nameRect = element.getBoundingClientRect();

// 		var padding = js.Browser.window.getComputedStyle(element).getPropertyValue;
// 		if (moveFlags.has(Reparent) && event.clientX > nameRect.left + 100) {
// 			return In;
// 		}

// 		if (event.clientY > rect.top + rect.height / 2) {
// 			return Bot;
// 		}
// 		return Top;
// 	}

// 	function getElement(item : TreeItem, parent: TreeItem, depth: Int) : js.html.Element {
// 		var data = getDataOrRoot(item);
// 		data.depth = depth;
// 		data.parent = parent;

// 		if (data.element == null) {
// 			data.element = js.Browser.document.createElement("fancy-tree-item");
// 			data.element.style.setProperty("--depth", Std.string(depth));

// 			var header = js.Browser.document.createElement("fancy-tree-header");
// 			data.header = header;
// 			data.element.append(header);
// 			refreshHeader(data);
// 		}

// 		data.path = getDataOrRoot(parent).path + "/" + getUniqueName(item);

// 		refreshItemSelection(item, selection.get(cast item) ?? false);

// 		return data.element;
// 	}

// 	public function clearSelection() {
// 		for (item => _ in selection) {
// 			var item : TreeItem = cast item;
// 			refreshItemSelection(item, false);
// 		}
// 		selection.clear();
// 	}

// 	public function setSelection(item: TreeItem, newStatus: Bool) {
// 		if (newStatus == true)
// 			selection.set(cast item, true);
// 		else
// 			selection.remove(cast item);
// 		refreshItemSelection(item, newStatus);
// 	}

// 	public function setCurrent(item: TreeItem) {
// 		if (currentItem != null) {
// 			var data = getDataOrRoot(currentItem);
// 			data?.element?.classList.remove("current");
// 		}
// 		currentItem = item;
// 		var data = getDataOrRoot(item);
// 		data?.element?.classList.add("current");

// 		ensureVisible(data);
// 	}

// 	public function ensureVisible(data: TreeItemData<TreeItem>) {
// 		if (data?.element != null) {
// 			var root = element.get(0);
// 			var rootRect = root.getBoundingClientRect();
// 			var elemRect = data.element.getBoundingClientRect();

// 			if (elemRect.top < rootRect.top) {
// 				data.element.scrollIntoView(true);
// 			}

// 			if (elemRect.bottom > rootRect.bottom) {
// 				data.element.scrollIntoView(false);
// 			}
// 		}
// 	}

// 	public function flattenTreeItems() : Array<TreeItem> {
// 		var flat : Array<TreeItem> = [];
// 		function flatten(item: TreeItem) {
// 			var data = getDataOrRoot(item);
// 			if (!data.passSearch)
// 				return;
// 			if (item != null)
// 				flat.push(item);

// 			if (data.children != null && isDataVisuallyOpen(data)) {
// 				for (child in data.children) {
// 					flatten(child);
// 				}
// 			}
// 		}
// 		flatten(null);
// 		return flat;
// 	}

// 	public function moveCurrent(delta: Int) {
// 		if (delta == 0)
// 			return;

// 		var flat = flattenTreeItems();

// 		var currentIndex = flat.indexOf(currentItem);
// 		if (currentIndex < 0) {
// 			if (rootData.children == null)
// 				return;

// 			currentItem = flat[0];
// 			setCurrent(currentItem);

// 			if (searchBar.isOpen() && searchBar.hasFocus()) {
// 				searchBar.blur();
// 				element.focus();
// 			}
// 			return;
// 		}

// 		var nextIndex = currentIndex + delta;
// 		if (nextIndex < 0) {
// 			if (searchBar.isOpen()) {
// 				searchBar.focus();
// 				setCurrent(null);
// 				return;
// 			}
// 			else {
// 				nextIndex = 0;
// 			}
// 		}
// 		else {
// 			if (searchBar.isOpen() && searchBar.hasFocus()) {
// 				searchBar.blur();
// 				element.focus();
// 			}
// 		}

// 		if (nextIndex > flat.length-1)
// 			nextIndex = flat.length-1;

// 		if (nextIndex != currentIndex) {
// 			setCurrent(flat[nextIndex]);
// 		}
// 	}

// 	function refreshItemSelection(item: TreeItem, status: Bool) {
// 		var data = itemMap.get(cast item);
// 		if (data?.element == null)
// 			return;
// 		data.element.classList.toggle("selected", status);
// 	}
// }