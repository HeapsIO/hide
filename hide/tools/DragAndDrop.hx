package hide.tools;

enum DragEvent {
	Start;
	Stop;
}

enum DropEvent {
	Move;
	Enter;
	Leave;
	Drop;
}

enum OnDragEventResult {
	Allow;
	Cancel;
}

enum OnDropEventResult {
	AllowDrop;
	ForbidDrop;
}

@:allow(hide.tools.DragAndDrop)
class DragData {
	var data: Map<String, Dynamic> = [];
	var sourceElement : DragElement = null;
	var thumbnail : js.html.Element;

	public function setThumbnail(element: js.html.Element) : Void {
		if (thumbnail != null)
			throw "already has thumbnail";
		var clone = element.cloneNode(true);
		var container = js.Browser.document.createElement("fancy-drag-drop-thumbnail");
		container.appendChild(clone);
		thumbnail = container;
		js.Browser.document.body.appendChild(container);
		untyped container.popover = "manual";
		untyped container.showPopover();
	}

	public function setThumbnailVisiblity(visible: Bool) : Void {

	}

	function new(sourceElement: DragElement) {
		this.sourceElement = sourceElement;
	};

	function dispose() {
		if (thumbnail != null) {
			thumbnail.remove();
		}
	}
}

class DropTarget extends js.html.Element {
	public var onHideDropEvent : (event: DropEvent, data: DragData) -> OnDropEventResult = null;
}

class DragElement extends js.html.Element {
	public var onHideDragEvent : (event: DragEvent, data: DragData) -> OnDragEventResult = null;
}

class DragAndDrop {
	static var currentDrag : DragData = null;
	static var currentDropTarget : DropTarget = null;

	static public function makeDraggable(element: js.html.Element, onDrag : (event: DragEvent, data: DragData) -> OnDragEventResult) : Void {
		element.addEventListener("pointerdown", onPointerDown, {capture: true});
		var dragElement : DragElement = cast element;
		dragElement.onHideDragEvent = onDrag;
	}

	static public function makeDropTarget(element: js.html.Element, onEvent: (event: DropEvent, data: DragData) -> OnDropEventResult) : Void {
		var dropTarget : DropTarget = cast element;
		dropTarget.onHideDropEvent = onEvent;
	}

	static function onPointerDown(e:js.html.PointerEvent) : Void {
		var element : js.html.Element = cast e.currentTarget;
		e.stopPropagation();
		element.addEventListener("pointermove", onPointerMove, {capture: true});
		element.addEventListener("pointerup", onPointerUp, {capture: true});
		element.setPointerCapture(e.pointerId);
	}

	static function onPointerMove(e:js.html.PointerEvent) : Void {
		var element : DragElement = cast e.currentTarget;
		if (element.onHideDragEvent == null)
			throw "Element is not a valid DragElement";
		e.stopImmediatePropagation();
		e.stopPropagation();
		e.preventDefault();

		if (currentDrag == null) {
			currentDrag = new DragData(element);
			switch(element.onHideDragEvent(Start, currentDrag)) {
				case Cancel:
					currentDrag = null;
					return;
				case Allow:
			}
			currentDropTarget = null;
		}

		var dropCandidates = js.Browser.document.elementsFromPoint(e.clientX, e.clientY);

		if (currentDrag.thumbnail != null) {
			var rect = currentDrag.thumbnail.getBoundingClientRect();
			currentDrag.thumbnail.style.left = '${e.clientX - rect.width / 2}px';
			currentDrag.thumbnail.style.top = '${e.clientY - rect.height + 4}px';
		}

		var foundDropTarget : DropTarget = null;
		for (dropCandidate in dropCandidates) {
			var dropTarget = cast dropCandidate;
			if (dropTarget.onHideDropEvent != null) {
				foundDropTarget = dropTarget;
				break;
			}
		}

		if (foundDropTarget != currentDropTarget) {
			currentDropTarget?.onHideDropEvent(Leave, currentDrag);
			currentDropTarget = foundDropTarget;
			currentDropTarget?.onHideDropEvent(Enter, currentDrag);
		}

		var result = currentDropTarget?.onHideDropEvent(Move, currentDrag) ?? ForbidDrop;

		// because we captured the pointer, the pointer is still considered over element, and so changing it's cursor
		// allow us to controll the appearance of the mouse pointer
		switch (result) {
			case AllowDrop:
				element.style.cursor = "auto";
			case ForbidDrop:
				element.style.cursor = "no-drop";
		}
	}

	static function onPointerUp(e:js.html.PointerEvent) : Void {
		var element : DragElement = cast e.currentTarget;
		element.removeEventListener("pointermove", onPointerMove, {capture: true});

		if (currentDrag != null) {
			e.stopImmediatePropagation();
			e.stopPropagation();
			e.preventDefault();
			element.style.cursor = null;
			currentDropTarget?.onHideDropEvent(Leave, currentDrag);
			currentDropTarget?.onHideDropEvent(Drop, currentDrag);
			currentDropTarget = null;
			currentDrag.dispose();
			currentDrag = null;
		}
	}

}