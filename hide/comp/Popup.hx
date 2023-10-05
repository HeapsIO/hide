package hide.comp;

import js.Browser;

// Open a "popup" window that can be closed by
// clicking outside of it. Usefull for medium size editors
// that appears when clicking on an item
class Popup extends Component {
	var popup : Element;
	var timer : haxe.Timer;
	var isSearchable:Bool;

	function onMouseDown(e : js.html.MouseEvent) {
		originalTarget = e.target;
	};

	function onMouseUp(e : js.html.MouseEvent) {
		var elem = new Element(originalTarget);
		if (originalTarget != null && canCloseOnClickOutside() && onShouldCloseOnClick(e) && elem.closest(popup).length == 0 && elem.closest(element).length == 0) {
			close();
		}
		originalTarget = null;
	}

	var originalTarget : js.html.EventTarget;

	public function new(?parent:Element, ?root:Element, isSearchable = false) {
		if( root == null ) root = new Element("<div>");
        super(parent,root);

		this.isSearchable = isSearchable;
		popup = new Element("<div>").addClass("popup");

		if (isSearchable) {
			var searchBar = new Element('<input type="text" class="search-bar" placeholder="Search ..."/>');
			popup.append(searchBar);

			searchBar.keyup((e) -> onSearchChanged(searchBar));
		}
		
		var body = root.closest(".lm_content");
		if (body.length == 0) body = new Element("body");
		body.append(popup);

		Browser.document.addEventListener("mousedown",onMouseDown);
		Browser.document.addEventListener("mouseup", onMouseUp);

		timer = new haxe.Timer(500);
		timer.run = function() {
			if( root.closest("body").length == 0 ) {
				close();
			}
		};

        reflow();
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
		var offset = element.offset();
		var popupHeight = popup.get(0).offsetHeight;
		var popupWidth = popup.get(0).offsetWidth;

		var clientHeight = Browser.document.documentElement.clientHeight;
		var clientWidth = Browser.document.documentElement.clientWidth;

		offset.top += element.get(0).offsetHeight;
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 32);

		//offset.left += element.get(0).offsetWidth;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 32);

		popup.offset(offset);
	}

	public function onSearchChanged(searchBar:Element):Void {}

	public function close() {
		timer.stop();
		popup.remove();
		Browser.document.removeEventListener("mousedown", onMouseDown);
		Browser.document.removeEventListener("mouseup", onMouseUp);
		onClose();
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
