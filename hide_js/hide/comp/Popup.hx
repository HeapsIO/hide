package hide.comp;

import js.Browser;

enum AnchorObject {
	/** client coordinates of the anchor's window **/
	Point(x: Float, y: Float);
	Element(element: js.html.Element);
}

/**
				Anchors :
               +--------------------------------+
               |                                |
               +--------------------------------+
StartOutside<--|-->S   t   r   e    t   c   h<--|-->EndOutside
               |-->StartInside  |  EndInside <--|
			                 Middle
	Start/End variants flip to the other side when the popup clips out of the page.
	Stretch sets the popup min size to the anchor size.
**/
enum AnchorDirection {
	StartOutside;
	StartInside;
	Stretch;
	Middle;
	EndInside;
	EndOutside;
}

typedef Anchor = {
	object: AnchorObject,
	directionX: AnchorDirection,
	directionY: AnchorDirection,
};

// Open a "popup" window that can be closed by
// clicking outside of it. Usefull for medium size editors
// that appears when clicking on an item
class Popup extends Component {
	var timer : haxe.Timer;
	var isSearchable:Bool;

	/** Below the parent element when null **/
	public var anchor(default, set) : Anchor;

	/** The element is kept in the DOM when closed, to be reopened with `open` **/
	public var keepAlive = false;

	/**
		Indicates if the user cancelled the popup operation with ESC
	**/
	public var wasCancelled: Bool = false;

	static inline var ANCHOR_MARGIN = 4;
	var flippedX = false;
	var flippedY = false;
	var resizeObserver : ResizeObserver;

	function set_anchor(v: Anchor) {
		anchor = v;
		flippedX = false;
		flippedY = false;
		if (resizeObserver != null)
			observeResize();
		reflow();
		return v;
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
	var mouseBlocker : js.html.Element;

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

			showPopover();
			element[0].addEventListener("toggle", onToggle);
			reflow();
		}

		// Make sure our element is focused so the whole ESC to dismiss properly works
		// (because our element steals inputs and prevent the event from escaping bellow it)
		element[0].focus();
	}

	public function open() {
		showPopover();
		element.show();
		element.get(0).addEventListener("toggle", onToggle);
		reflow();
	}

	/**
		Show the popup above a manual popover catching the mouse events of the page,
		including the click that light dismisses the popup.
	**/
	function showPopover() {
		var el = element[0];
		if (el.matches(":popover-open"))
			return;

		if (mouseBlocker == null)
			createMouseBlocker(el.ownerDocument);

		// a sibling, so that a click on it only dismisses the popups above its parent popup
		el.before(mouseBlocker);
		untyped mouseBlocker.showPopover();
		untyped el.showPopover();

		var win = el.ownerDocument.defaultView;
		win.addEventListener("scroll", onAnchorMoved, true);
		win.addEventListener("resize", onAnchorMoved);
		// direct call : observers run after layout, before paint, so the new position is painted in the same frame
		resizeObserver = new ResizeObserver((_, _) -> reflowInternal());
		observeResize();
	}

	function stopFollow() {
		var win = element[0].ownerDocument.defaultView;
		win.removeEventListener("scroll", onAnchorMoved, true);
		win.removeEventListener("resize", onAnchorMoved);
		resizeObserver?.disconnect();
		resizeObserver = null;
	}

	function observeResize() {
		resizeObserver.disconnect();
		resizeObserver.observe(element[0]);
		switch (getAnchor().object) {
			case Element(e) if (e != null):
				resizeObserver.observe(e);
			default:
		}
	}

	function onAnchorMoved(_: js.html.Event) {
		reflow();
	}

	function createMouseBlocker(doc : js.html.HTMLDocument) {
		mouseBlocker = doc.createDivElement();
		mouseBlocker.className = "popup-mouse-blocker";
		untyped mouseBlocker.popover = "manual";
		for (type in ["pointerdown", "pointerup", "mousedown", "mouseup", "click", "dblclick", "auxclick", "contextmenu", "wheel"])
			mouseBlocker.addEventListener(type, (e : js.html.Event) -> e.stopPropagation());
	}

	function onToggle(e: Dynamic) {
		if (e.newState == "open") {
			wasCancelled = false;
		}
		if (e.newState == "closed") {
			timer?.stop();
			mouseBlocker?.remove();
			stopFollow();
			var parent = element[0].parentElement;
			if (parent != null) {
				// Focus our parent when closing the popup, it allows
				// the ESC to dismiss the popup to properly work
				// when we are interracting in a nested popup scenario
				parent.focus();
			}

			if (!keepAlive) {
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

		var el = element[0];
		var a = getAnchor();
		var rect = getAnchorRect(a);
		if (rect == null)
			return;

		applyStretch(a, rect);
		var box = el.getBoundingClientRect();
		var page = el.ownerDocument.documentElement;
		var pos = place(a, rect, box.width, box.height, new js.html.DOMRect(0, 0, page.clientWidth, page.clientHeight));
		el.style.left = pos.x + "px";
		el.style.top = pos.y + "px";
	}

	function getAnchor() : Anchor {
		return anchor ?? { object: Element((detachParent ?? element.parent())[0]), directionX: StartInside, directionY: EndOutside };
	}

	function getAnchorRect(a: Anchor) : js.html.DOMRect {
		return switch (a.object) {
			case Point(x, y): new js.html.DOMRect(x, y, 0, 0);
			case Element(e): e?.getBoundingClientRect();
		}
	}

	function applyStretch(a: Anchor, rect: js.html.DOMRect) {
		var style = element[0].style;
		if (a.directionX == Stretch)
			style.minWidth = rect.width + "px";
		if (a.directionY == Stretch)
			style.minHeight = rect.height + "px";
	}

	/**
		Position of a popup of size `width` x `height` anchored to `rect`, inside `page`.
		On each axis, flips the direction if it makes the popup fit, otherwise clamps it into the page.
		The CSS variables `--anchor-gap-x` / `--anchor-gap-y` (px) offset Start/End variants away from the anchor edge.
	**/
	function place(a: Anchor, rect: js.html.DOMRect, width: Float, height: Float, page: js.html.DOMRect) {
		var el = element[0];
		var style = el.ownerDocument.defaultView.getComputedStyle(el);
		function getGap(name: String) {
			var v = Std.parseFloat(style.getPropertyValue(name));
			return Math.isNaN(v) ? 0. : v;
		}

		function placeAxis(dir: AnchorDirection, flipped: Bool, start: Float, end: Float, size: Float, min: Float, max: Float, gap: Float) {
			function getPos(flipped: Bool) {
				var d = !flipped ? dir : switch (dir) {
					case StartOutside: EndOutside;
					case EndOutside: StartOutside;
					case StartInside: EndInside;
					case EndInside: StartInside;
					default: dir;
				}
				return switch (d) {
					case StartOutside: start - size - gap;
					case StartInside: start + gap;
					case Stretch: start;
					case Middle: (start + end - size) / 2;
					case EndInside: end - size - gap;
					case EndOutside: end + gap;
				}
			}

			function clips(pos: Float) {
				return pos < min || pos + size > max;
			}

			var pos = getPos(flipped);
			if (clips(pos)) {
				var flippedPos = getPos(!flipped);
				if (clips(flippedPos))
					pos = Math.max(min + ANCHOR_MARGIN, Math.min(pos, max - size - ANCHOR_MARGIN));
				else {
					flipped = !flipped;
					pos = flippedPos;
				}
			}
			return { pos: Math.round(pos), flipped: flipped };
		}

		var x = placeAxis(a.directionX, flippedX, rect.left, rect.right, width, page.left, page.right, getGap("--anchor-gap-x"));
		var y = placeAxis(a.directionY, flippedY, rect.top, rect.bottom, height, page.top, page.bottom, getGap("--anchor-gap-y"));
		flippedX = x.flipped;
		flippedY = y.flipped;
		return { x: x.pos, y: y.pos };
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
		timer = new haxe.Timer(500);
		timer.run = () -> switch (getAnchor().object) {
			case Element(e) if (e != null && !e.isConnected): close();
			default:
		};

		mouseBlocker?.remove();
		stopFollow();
		el.removeAttribute("popover");
		el.style.removeProperty("top");
		el.style.removeProperty("left");
		el.classList.add("detached");

		// screenX includes the invisible resize border on the left, unlike the window.open / moveTo coordinates
		function toScreen(win : js.html.Window, x : Float, y : Float) {
			return { x: win.screenX + (win.outerWidth - win.innerWidth) / 2 + x, y: win.screenY + y };
		}

		var parentWindow = detachParent?.get(0)?.ownerDocument.defaultView ?? oldWindow;

		function getAnchorScreenRect(a: Anchor) {
			var r = getAnchorRect(a) ?? new js.html.DOMRect();
			var win = switch (a.object) {
				case Element(e) if (e != null): e.ownerDocument.defaultView;
				default: parentWindow;
			}
			var p = toScreen(win, r.left, r.top);
			return new js.html.DOMRect(p.x, p.y, r.width, r.height);
		}

		if (autoDetached) {
			var r = getAnchorScreenRect(getAnchor());
			// hidden until placed
			subWindow = new SubWindow(1, 1, null, r.left, r.bottom, parentWindow, false);
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

		var style = win.getComputedStyle(el);
		function px(v: String) return StringTools.endsWith(v, "px") ? Std.parseFloat(v) : 0.;
		var contentBox = style.boxSizing != "border-box";
		var minWidth = px(style.minWidth);
		if (minWidth > 0)
			subWindow.minWidth = Math.ceil(contentBox ? minWidth + px(style.paddingLeft) + px(style.paddingRight) + px(style.borderLeftWidth) + px(style.borderRightWidth) : minWidth);
		var minHeight = px(style.minHeight);
		if (minHeight > 0)
			subWindow.minHeight = Math.ceil(contentBox ? minHeight + px(style.paddingTop) + px(style.paddingBottom) + px(style.borderTopWidth) + px(style.borderBottomWidth) : minHeight);

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

			// the click on the parent window that closes the popup must not reach its content
			createMouseBlocker(parentWindow.document);
			parentWindow.document.body.append(mouseBlocker);
			untyped mouseBlocker.showPopover();

			// fit the content, filled after the constructor
			win.requestAnimationFrame((_) -> {
				var a = getAnchor();
				var rect = getAnchorScreenRect(a);
				applyStretch(a, rect);
				el.style.position = "absolute";
				el.style.width = "max-content";
				var size = el.getBoundingClientRect();
				el.style.removeProperty("position");
				el.style.removeProperty("width");

				var w = Math.ceil(size.width);
				var h = Math.ceil(size.height);
				var screen = win.screen;
				var pos = place(a, rect, w, h, new js.html.DOMRect(screen.availLeft, screen.availTop, screen.availWidth, screen.availHeight));

				// both take content bounds but keep the other half from the frame bounds :
				// moveTo sets the outer size as content size, resizeTo sets screenX (left border included) as content x
				var border = (win.outerWidth - win.innerWidth) / 2;
				win.moveTo(Std.int(pos.x + border), Std.int(pos.y));
				// at least 100x100 for script resized windows
				win.resizeTo(w, h);

				// resizeTo is applied asynchronously
				if (win.innerWidth == w && win.innerHeight == h)
					subWindow.show();
				else
					win.addEventListener("resize", (_) -> subWindow.show(), { once: true });
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
