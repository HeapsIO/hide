package hide.comp;

import js.Browser;

// Open a "popup" window that can be closed by
// clicking outside of it. Usefull for medium size editors
// that appears when clicking on an item
class Popup extends Component {
	var timer : haxe.Timer;
	var isSearchable:Bool;
	public var anchor : Element;
	var globalKeyListener : Dynamic = null;

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

	public function new(?parent:Element, isSearchable = false) {
      super(parent,new Element("<div>"));

		element.attr("popover", "").addClass("popup");

		element[0].addEventListener("dblclick", (e) -> {e.stopPropagation();});

		this.isSearchable = isSearchable;

		if (isSearchable) {
			var searchBar = new Element('<input type="text" class="search-bar" placeholder="Search ..."/>');
			element.append(searchBar);

			searchBar.keyup((e) -> onSearchChanged(searchBar));
		}

		var body = parent.closest(".lm_content");
		if (body.length == 0) body = new Element("body");

		timer = new haxe.Timer(500);
		timer.run = function() {
			if( parent.closest("body").length == 0 ) {
				close();
			}
		};

		untyped element.get(0).showPopover();
		element.get(0).addEventListener("toggle", onToggle);
        reflow();
	}

	public function bindCloseOnEscape() {
		globalKeyListener = (e: js.html.KeyboardEvent) -> {
			// in case somehow our event wasn't properly cleaned up
			if (element.closest("body") == null) {
				cleanupGlobalKeyListener();
				return;
			}

			if (e.key == "Escape") {
				close();
				e.preventDefault();
				e.stopPropagation();
			}
		};

		Browser.document.addEventListener("keydown", globalKeyListener, true);
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
		if (e.newState == "closed") {
			timer.stop();
			element.parent()?.get(0)?.removeEventListener("scroll", onScroll);
			if (anchor == null) {
				element.remove();
			}
			element.hide();
			onClose();
			if (globalKeyListener != null) {
				cleanupGlobalKeyListener();
			}
		}
	}

	function cleanupGlobalKeyListener() {
		Browser.document.removeEventListener("keydown", globalKeyListener, true);
		globalKeyListener = null;
	}

	function fixInputSelect() {
		var e = new Element("input");
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

	function reflow() {
		var refElement = if (anchor != null) anchor else element.parent();
		var offset = refElement.offset();
		var popupHeight = element.get(0).offsetHeight;
		var popupWidth = element.get(0).offsetWidth;

		var clientHeight = Browser.document.documentElement.clientHeight;
		var clientWidth = Browser.document.documentElement.clientWidth;

		offset.top += refElement.get(0).offsetHeight;
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 16);

		//offset.left += element.get(0).offsetWidth;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 16);

		element.offset(offset);
	}

	public function onSearchChanged(searchBar:Element):Void {}

	public function close() {
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
