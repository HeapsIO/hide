package hide.comp;

enum Side {
	None;
	Left;
	Right;
	Top;
	Bottom;
}

class DetachablePanel extends hide.comp.Component {
	// don't touch the width ? on resize check the new height to not go beyond min bottom

	var currentSide = Side.None;
	public var defaultState = {
		left : "20%",
		right : "620px",
		bottom : "20px",
		top : "unset",
		width : "unset",
	};
	public var minWidth = 300;
	public var minBottom = 20;

	public function new(?parent : Element, ?el : Element) {
		super(parent, el);
		element.addClass("detachable-panel");
		var layoutControls = new Element('<div class="layout-controls">
			<div class="splitter horizontal handle-right"><div class="drag-handle"></div></div>
			<div class="splitter horizontal handle-left"><div class="drag-handle"></div></div>
			<div class="splitter vertical handle-top"><div class="drag-handle"></div></div>
		</div>');
			// <div class="splitter vertical handle-bottom"><div class="drag-handle"></div></div>

		var document = new Element(js.Browser.document);

		var startState = { x : 0, y : 0, left : 0, right : 0, top : 0, bottom : 0, width : 0, height : 0 };
		function initDrag(e : js.jquery.Event) {
			startState = {
				x : e.clientX,
				y : e.clientY,
				left : Std.parseInt(element.css("left")),
				right : Std.parseInt(element.css("right")),
				top : Std.parseInt(element.css("top")),
				bottom : Std.parseInt(element.css("bottom")),
				width : Std.parseInt(element.css("width")),
				height : Std.parseInt(element.css("height")),
			}
			element.css("width", startState.width + "px");
			element.css("right", "unset");
		}

		layoutControls.find(".handle-right .drag-handle").first().mousedown((e : js.jquery.Event) -> {
			currentSide = Right;
			initDrag(e);
		});
		layoutControls.find(".handle-left .drag-handle").first().mousedown((e : js.jquery.Event) -> {
			currentSide = Left;
			initDrag(e);
		});
		layoutControls.find(".handle-top .drag-handle").first()
			.mousedown((e : js.jquery.Event) -> {
				currentSide = Top;
				initDrag(e);
			})
			.dblclick((e) -> {
				e.preventDefault();
				resetLayout();
			});

		document.mousemove((e : js.jquery.Event) -> {
			switch (currentSide) {
			case Left:
				e.stopPropagation();
				var newLeft = e.clientX;
				if( newLeft < 0 )
					return;
				var diff = newLeft - startState.left;
				var newWidth = startState.width - diff;
				if( newWidth < minWidth ) {
					newLeft = startState.left + startState.width - minWidth;
					newWidth = minWidth;
				}
				element.css("left", newLeft + "px");
				element.css("width", newWidth + "px");
			case Right:
				e.stopPropagation();
				var newWidth = startState.width + e.clientX - startState.x;
				if( startState.left + newWidth > js.Browser.window.innerWidth )
					newWidth = Std.int(js.Browser.window.innerWidth) - e.clientX;
				if( newWidth < minWidth )
					newWidth = minWidth;
				element.css("width", newWidth + "px");
			case Top:
				e.stopPropagation();
				var diffx = startState.x - e.clientX;
				var newLeft = startState.left - diffx;
				if( newLeft < 0 )
					newLeft = 0;
				if( newLeft + startState.width > js.Browser.window.innerWidth )
					newLeft = Std.int(js.Browser.window.innerWidth) - startState.width;
				element.css("left", newLeft + "px");
			case Bottom:
			case None:
			}
		});
		document.mouseleave((_) -> {
			currentSide = None;
		});
		document.mouseup((_) -> {
			currentSide = None;
			saveLayout();
		});

		layoutControls.appendTo(element);
	}

	function saveLayout() {
		var toSave = element.css(["left", "right"]);
		if( toSave != null )
			saveDisplayState("detachedOffsets", toSave);
	}

	public function resetLayout() {
		element.css(defaultState);
		saveDisplayState("detachedOffsets", {});
	}

	public function setDetached(val) {
		element.toggleClass("detached", val);
		var existingState = getDisplayState("detachedOffsets");
		if( existingState != null )
			element.css(existingState);
	}
}
