package hide.comp;

import js.Browser;

enum PopupPosition {
	Inside;
	Bellow;
}
// Open a "popup" window that can be closed by
// clicking outside of it. Usefull for medium size editors
// that appears when clicking on an item
class Popup extends Component {
	var timer : haxe.Timer;
	var isSearchable:Bool;
	public var anchor : Element;
	public var offsetX(default, set) : Float = 0;
	public var offsetY(default, set) : Float = 0;
	public var position(default, set): PopupPosition = Bellow;

	/**
		Indicates if the user cancelled the popup operation with ESC
	**/
	public var wasCancelled: Bool = false;

	function set_offsetX(v) {
		offsetX = v;
		reflow();
		return offsetX;
	}

	function set_offsetY(v) {
		offsetY = v;
		reflow();
		return offsetY;
	}

	function set_position(v) {
		position = v;
		reflow();
		return position;
	}

	function onMouseDown(e : js.html.MouseEvent) {
		originalTarget = e.target;
	};

	function onMouseUp(e : js.html.MouseEvent) {
		var elem = new Element(originalTarget);
		if (originalTarget != null && canCloseOnClickOutside() && onShouldCloseOnClick(e) && elem.closest(element).length == 0 && elem.closest(element).length == 0) {
			close();
		}
		originalTarget = null;
	}

	var originalTarget : js.html.EventTarget;

	var subWindow : SubWindow;
	var blurDismiss = false;
	// parent element of an auto detached popup, its window position comes from it
	var detachParent : Element;
	var parentPopup : Popup;
	var childPopups : Array<Popup> = [];

	public function new(?parent:Element, isSearchable = false) {
		// a popup opened from a popup window would be clipped by it
		var autoDetach = getWindowPopup(parent?.get(0)?.ownerDocument.defaultView) != null;
	  	super(autoDetach ? null : parent,new Element("<div>"));

		element.attr("tabindex", "-1").attr("popover", "auto").addClass("popup");

		element[0].addEventListener("dblclick", (e) -> {e.stopPropagation();});

		// Prevent parent elements from e.preventDefault(), which would break the
		// ESC to dismiss the popover behavior. Once detached, the ESC reaches SubWindow.onKeyDown
		element[0].addEventListener("keydown", (e: js.html.KeyboardEvent) -> {if (subWindow == null) e.stopPropagation(); wasCancelled = wasCancelled || e.key == "Escape";});

		this.isSearchable = isSearchable;

		if (isSearchable) {
			var searchBar = new Element('<input type="text" class="search-bar" placeholder="Search ..."/>');
			element.append(searchBar);

			searchBar.keyup((e) -> onSearchChanged(searchBar));
		}

		if (autoDetach) {
			detachParent = parent;
			detach(true);
		} else {
			timer = new haxe.Timer(500);
			timer.run = function() {
				if( parent.closest("body").length == 0 ) {
					close();
				}
			};

			untyped element[0].showPopover();
			element[0].addEventListener("toggle", onToggle);
			reflow();
		}

		// Make sure our element is focused so the whole ESC to dismiss properly works
		// (because our element steals inputs and prevent the event from escaping bellow it)
		element[0].focus();
	}

	public function open() {
		untyped element.get(0).showPopover();
		element.show();
		element.get(0).addEventListener("toggle", onToggle);
		element.parent()?.get(0)?.addEventListener("scroll", onScroll);
		reflow();
	}

	public function onScroll(e: js.html.MouseScrollEvent) {
		reflow();
	}

	function onToggle(e: Dynamic) {
		if (e.newState == "open") {
			wasCancelled = false;
		}
		if (e.newState == "closed") {
			timer?.stop();
			var parent = element[0].parentElement;
			if (parent != null) {
				// Focus our parent when closing the popup, it allows
				// the ESC to dismiss the popup to properly work
				// when we are interracting in a nested popup scenario
				parent.focus();

				parent.removeEventListener("scroll", onScroll);
			}

			if (anchor == null) {
				element.remove();
			}
			element.hide();
			onClose();
		}
	}

	function fixInputSelect() {
		var e = element.find("input");
		e.each(function (id : Int, elem : js.html.Element) {
			if (elem.onpointerdown == null && elem.onpointerup == null) {
				elem.onpointerdown = function(event : js.html.PointerEvent) {
					elem.setPointerCapture(event.pointerId);
				};

				elem.onpointerup = function(event : js.html.PointerEvent) {
					elem.releasePointerCapture(event.pointerId);
				};
			}
		});
	}

	var reflowQueued = false;
	function reflow() {
		if (!reflowQueued && subWindow == null) {
			reflowQueued = true;
			element[0].ownerDocument.defaultView.requestAnimationFrame((_) -> reflowInternal());
		}
	}

	function reflowInternal() {
		reflowQueued = false;
		if (subWindow != null)
			return;

		var refElement = if (anchor != null) anchor else element.parent();
		var offset = refElement.offset();
		var box = element[0].getBoundingClientRect();
		var popupHeight = box.height;
		var popupWidth = box.width;

		var clientHeight = element[0].ownerDocument.documentElement.clientHeight;
		var clientWidth = element[0].ownerDocument.documentElement.clientWidth;

		offset.top += offsetY;
		if (position == Bellow) {
			offset.top += refElement.get(0).offsetHeight;
		}
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 16);

		offset.left += offsetX;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 16) ;

		element.offset(offset);
	}

	/**
		Move the popup into its own window, until it is closed.
		`autoDetached` : opened from a popup window, sized to its content, without title bar, closed on blur and with its parent popup.
		Otherwise the window bounds are saved.
	**/
	public function detach(autoDetached : Bool, ?title : String) {
		if (subWindow != null)
			return;

		var el = element[0];
		var oldWindow = el.ownerDocument.defaultView;
		var rect = el.getBoundingClientRect();
		detachParent ??= element.parent();

		el.removeEventListener("toggle", onToggle);
		timer?.stop();
		el.removeAttribute("popover");
		el.style.removeProperty("top");
		el.style.removeProperty("left");
		el.classList.add("detached");

		// screenX includes the invisible resize border on the left, unlike the window.open / moveTo coordinates
		function toScreen(win : js.html.Window, x : Float, y : Float) {
			return { x: win.screenX + (win.outerWidth - win.innerWidth) / 2 + x, y: win.screenY + y };
		}

		function getAnchorScreenPos() {
			var ref = (anchor ?? detachParent)[0];
			var r = ref.getBoundingClientRect();
			return toScreen(ref.ownerDocument.defaultView, r.left + offsetX, (position == Bellow ? r.bottom : r.top) + offsetY);
		}

		var parentWindow = detachParent?.get(0)?.ownerDocument.defaultView ?? oldWindow;
		if (autoDetached) {
			var pos = getAnchorScreenPos();
			subWindow = new SubWindow(1, 1, null, pos.x, pos.y, parentWindow);
		} else {
			var pos = toScreen(oldWindow, rect.left, rect.top);
			subWindow = new SubWindow(Math.ceil(rect.width), Math.ceil(rect.height), "popupSubwindow/" + componentName, pos.x, pos.y, parentWindow);
		}

		var win = subWindow.window;
		untyped win.__popup_subwindow = this;
		win.document.body.classList.add("popup-sub-window");
		if (title != null)
			subWindow.title = title;
		win.document.body.appendChild(el);

		subWindow.onKeyDown = (e) -> if (e.key == "Escape") {
			wasCancelled = true;
			close();
		};
		subWindow.onClose = () -> {
			for (c in childPopups.copy())
				c.close();
			parentPopup?.childPopups.remove(this);
			onToggle({newState: "closed"});
		};

		if (autoDetached) {
			win.document.body.classList.add("auto-detached");
			blurDismiss = true;
			parentPopup = getWindowPopup(detachParent?.get(0)?.ownerDocument.defaultView);
			parentPopup?.childPopups.push(this);
			win.addEventListener("blur", (_) -> closeIfUnfocused());

			// fit the content, filled after the constructor
			win.requestAnimationFrame((_) -> {
				el.style.position = "absolute";
				el.style.width = "max-content";
				var size = el.getBoundingClientRect();
				el.style.removeProperty("position");
				el.style.removeProperty("width");

				var w = Math.ceil(size.width);
				var h = Math.ceil(size.height);
				var pos = getAnchorScreenPos();
				var screen = win.screen;
				var x = Math.max(screen.availLeft, Math.min(pos.x, screen.availLeft + screen.availWidth - w));
				var y = Math.max(screen.availTop, Math.min(pos.y, screen.availTop + screen.availHeight - h));

				// both take content bounds but keep the other half from the frame bounds :
				// moveTo sets the outer size as content size, resizeTo sets screenX (left border included) as content x
				var border = (win.outerWidth - win.innerWidth) / 2;
				win.moveTo(Std.int(x + border), Std.int(y));
				// at least 100x100 for script resized windows
				win.resizeTo(w, h);
			});
		}

		el.focus();
	}

	function closeIfUnfocused() {
		// the newly focused window is only known after the blur
		haxe.Timer.delay(() -> {
			function hasFocus(p : Popup) : Bool {
				return p.subWindow.window.document.hasFocus() || Lambda.exists(p.childPopups, hasFocus);
			}
			if (subWindow.window.closed || hasFocus(this))
				return;
			close();
			if (parentPopup != null && parentPopup.blurDismiss)
				parentPopup.closeIfUnfocused();
		}, 0);
	}

	static function getWindowPopup(win : js.html.Window) : Popup {
		return win == null ? null : untyped win.__popup_subwindow;
	}

	public function onSearchChanged(searchBar:Element):Void {}

	public function close() {
		if (subWindow != null) {
			subWindow.close();
			return;
		}
		untyped element.get(0).hidePopover();
		onToggle({newState: "closed"});
	}

	public dynamic function onClose() {
	}

	public function canCloseOnClickOutside() : Bool {
		return true;
	}

	public dynamic function onShouldCloseOnClick(clickEvent : js.html.Event) : Bool {
		return true;
	}
}
