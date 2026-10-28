package hide.html.comp;

import hide.html.WebComponent;
import js.Browser.document;
import js.html.*;
import hrt.ui.HuiMenu.MenuItem;

/**
	Shows a tab bar with one tab per child (text from its `label` attribute, tooltip from `tab-title`) and only displays the child of the selected tab.
	Tabs from the first one that doesn't fit in the bar are hidden and listed in a dropdown, which moves the picked tab to the front.
	With `auto-hide-empty`, it is hidden while empty, except during a tab drag it accepts.
	Tabs can't be dragged unless a subclass overrides `canDragPane` and `canDropPane`.
**/
@:keep
class TabContainer extends WebComponent {
	static var dragged : Element;
	static var dragSource : TabContainer;
	static inline var DRAG_TYPE = "application/x-hide-tab";

	var tabs : DivElement;
	var more : DivElement;
	var view : SlotElement;
	var selected : Element;
	var observer : MutationObserver;

	public function new() {
		super();
		var root = attachShadow(cast {mode: "open", slotAssignment: "manual"});
		root.adoptedStyleSheets = [styleSheet];

		tabs = document.createDivElement();
		tabs.className = "tabs";
		tabs.setAttribute("part", "tabs");
		ondragover = (e : DragEvent) -> {
			if (!canDrop(e))
				return;
			e.preventDefault();
			e.dataTransfer.dropEffect = "move";
			classList.add("drop");
		};
		// dragenter must accept too, or entering a child resets the drop effect until the next dragover.
		// Listened on the root : between two shadow elements, the host gets no dragenter (target and relatedTarget both retarget to it)
		root.addEventListener("dragenter", ondragover);
		ondragleave = (e : DragEvent) -> if (!contains(cast e.relatedTarget)) classList.remove("drop");
		ondrop = (e : DragEvent) -> drop(e);
		new hide.comp.ResizeObserver((_, _) -> updateOverflow()).observe(tabs);

		more = document.createDivElement();
		more.className = "more";
		more.setAttribute("part", "more");
		more.textContent = "▾";
		more.hidden = true;
		more.onclick = () -> {
			var items : Array<MenuItem> = [];
			for (i in 0...tabs.children.length) {
				if (!tabs.children[i].hidden)
					continue;
				var pane = children[i];
				items.push({label: tabs.children[i].firstChild.textContent, click: () -> {
					insertPane(pane, firstElementChild);
					select(pane);
				}});
			}
			hide.comp.ContextMenu.createDropdown(more, items);
		};

		var header = document.createDivElement();
		header.className = "header";
		header.append(tabs, more);
		view = document.createSlotElement();
		root.append(header, view);

		observer = new MutationObserver((_, _) -> build());
	}

	override public function connectedCallback() {
		build();
	}

	function build() {
		// Only direct children matter: a subtree observer would get the records of every view below
		observer.disconnect();
		observer.observe(this, {childList: true});
		for (i in 0...children.length)
			observer.observe(children[i], {attributes: true, attributeFilter: ["label", "tab-title"]});

		var panes = [for (i in 0...children.length) children[i]];
		if (panes.indexOf(selected) < 0) {
			// Removed without close() : it may be destroyed, or shown by another container
			selected = null;
			select(panes[0]);
		}

		// dragend never reaches a removed tab, so its drag is cancelled
		if (dragSource == this && dragged != null)
			endDrag();

		refreshAutoHide();

		tabs.innerHTML = "";
		for (i => pane in panes) {
			var tab = document.createDivElement();
			tab.className = pane == selected ? "tab selected" : "tab";
			tab.setAttribute("part", "tab");
			tab.textContent = pane.getAttribute("label") ?? 'Tab ${i + 1}';
			tab.title = pane.getAttribute("tab-title") ?? "";

			tab.onclick = () -> select(pane);
			tab.onmousedown = (e : MouseEvent) -> if (e.button == 1) e.preventDefault();
			tab.onauxclick = (e : MouseEvent) -> if (e.button == 1) close(pane);
			tab.oncontextmenu = (e : MouseEvent) -> {
				e.preventDefault();
				var items = buildPaneMenu(pane);
				if (items.length > 0)
					hide.comp.ContextMenu.createFromEvent(e, items);
			};

			var closeButton = document.createSpanElement();
			closeButton.className = "close";
			closeButton.setAttribute("part", "close");
			closeButton.textContent = "×";
			closeButton.onclick = (e : MouseEvent) -> {
				e.stopPropagation();
				close(pane);
			};
			tab.append(closeButton);

			tab.draggable = canDragPane(pane);
			tab.ondragstart = (e : DragEvent) -> {
				e.dataTransfer.effectAllowed = "move";
				e.dataTransfer.setData(DRAG_TYPE, "");
				dragged = pane;
				dragSource = this;
				// Changing the layout in dragstart can cancel the drag
				haxe.Timer.delay(() -> if (dragged == pane) refreshAllAutoHide(), 0);
			};
			tab.ondragend = () -> endDrag();

			tabs.append(tab);
		}

		updateOverflow();
	}

	function updateOverflow() {
		for (i in 0...tabs.children.length)
			tabs.children[i].hidden = false;

		more.hidden = tabs.scrollWidth <= tabs.clientWidth;
		if (more.hidden)
			return;

		var right = tabs.getBoundingClientRect().right;
		var overflow = false;
		for (i in 0...tabs.children.length) {
			var tab = tabs.children[i];
			overflow = overflow || tab.getBoundingClientRect().right > right;
			tab.hidden = overflow;
		}
	}

	function canDragPane(pane : Element) {
		return false;
	}

	function canDropPane(pane : Element, from : TabContainer) {
		return false;
	}

	/** Return false to cancel the close **/
	function canClosePane(pane : Element) {
		return true;
	}

	function buildPaneMenu(pane : Element) : Array<MenuItem> {
		return [
			{label: "Close", click: () -> close(pane)},
			{label: "Close Others", click: () -> for (p in [for (i in 0...children.length) children[i]]) if (p != pane) close(p)},
			{label: "Close All", click: () -> for (p in [for (i in 0...children.length) children[i]]) close(p)},
		];
	}

	function onPaneVisibilityChanged(pane : Element, visible : Bool) {
	}

	function insertPane(pane : Element, before : Element) {
		insertBefore(pane, before);
	}

	function canDrop(e : DragEvent) {
		return dragged != null && e.dataTransfer.types.indexOf(DRAG_TYPE) >= 0 && canDropPane(dragged, dragSource);
	}

	/**
		Non empty containers are left to the owner, which may hide them.
	**/
	function refreshAutoHide() {
		if (!hasAttribute("auto-hide-empty"))
			return;
		var empty = children.length == 0;
		var transient = empty && dragged != null && canDropPane(dragged, dragSource);
		classList.toggle("transientDrop", transient);
		if (empty && hidden == transient)
			hidden = !transient;
	}

	static function refreshAllAutoHide() {
		var list = document.querySelectorAll("[auto-hide-empty]");
		for (i in 0...list.length) {
			var tc = Std.downcast(list[i], TabContainer);
			if (tc != null)
				tc.refreshAutoHide();
		}
	}

	static function endDrag() {
		dragged = null;
		refreshAllAutoHide();
	}

	function drop(e : DragEvent) {
		e.preventDefault();
		classList.remove("drop");
		if (!canDrop(e))
			return;

		var pane = dragged;
		// The move rebuilds the tabs, so dragend may not reach the removed source tab
		dragged = null;

		var from : TabContainer = cast pane.parentElement;
		// Hand the source selection over before moving, so the pane isn't hidden after being shown here
		if (from != this && from.selected == pane)
			from.select(pane.nextElementSibling ?? pane.previousElementSibling);

		var next = null;
		// Dropped outside the tab bar : added last
		var onTabs = e.composedPath().indexOf(tabs) >= 0;
		for (i in 0...tabs.children.length) {
			var r = tabs.children[i].getBoundingClientRect();
			if (onTabs && e.clientX < r.left + r.width / 2) {
				next = children[i];
				break;
			}
		}

		insertPane(pane, next);
		select(pane);
		refreshAllAutoHide();
	}

	/**
		Removes `pane` unless `canClosePane` returns false. Returns true if it was removed.
	**/
	public function close(pane : Element) {
		if (!canClosePane(pane))
			return false;

		if (pane == selected)
			select(pane.nextElementSibling ?? pane.previousElementSibling);
		pane.remove();
		return true;
	}

	public function select(pane : Element) {
		if (pane == selected)
			return;

		function notify(pane : Element, visible : Bool)
			if (pane != null)
				onPaneVisibilityChanged(pane, visible);

		notify(selected, false);
		selected = pane;

		if (pane == null)
			view.assign();
		else
			view.assign(pane);

		for (i in 0...tabs.children.length)
			tabs.children[i].classList.toggle("selected", children[i] == pane);

		notify(pane, true);
	}

	static var _ = register(TabContainer, "hide-tab-container");
}
