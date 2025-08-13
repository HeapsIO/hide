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

enum DropTargetValidity {
	AllowDrop;
	ForbidDrop;
}

@:allow(hide.tools.DragAndDrop)
class DragData {
	public var mouseX : Int = 0;
	public var mouseY : Int = 0;
	public var shiftKey : Bool = false;

	public var data: Map<String, Dynamic> = [];
	public var sourceElement : DragElement = null;

	/** Allow to feedback to the user if the current drag operation has a valid target or no. Should be set from the onDrop event in makeDropTarget**/
	public var dropTargetValidity : DropTargetValidity = AllowDrop;

	var thumbnail : js.html.Element;
	var canceled : Bool = false;

	public function setThumbnail(element: js.html.Element) : Void {
		if (thumbnail != null)
			throw "already has thumbnail";
		var clone : js.html.Element = cast element.cloneNode(true);
		var container = js.Browser.document.createElement("fancy-drag-drop-thumbnail");
		clone.style.transform = null;
		clone.style.left = null;
		clone.style.top = null;
		clone.style.position = "static";
		clone.style.display = "block";
		container.appendChild(clone);
		thumbnail = container;
	}

	public function setThumbnailVisiblity(visible: Bool) : Void {
		thumbnail?.style.visibility = visible ? "visible" : "hidden";
	}

	/** Cancel the drag operation. Only valid when called by the onDrag callback of makeDraggable**/
	public function cancel() {
		canceled = true;
	}

	function new(sourceElement: DragElement) {
		this.sourceElement = sourceElement;
	};

	function dispose() {
		if (thumbnail != null) {
			thumbnail.remove();
		}
	}

	function copyFromMouseEvent(e: js.html.MouseEvent) {
		mouseX = e.clientX;
		mouseY = e.clientY;
		@:privateAccess hide.Ide.inst.syncMousePosition(e);
		shiftKey = e.shiftKey;
	}
}


class DropTarget extends js.html.Element {
	public var onHideDropEvent : (event: DropEvent, data: DragData) -> Void = null;
}

class DragElement extends js.html.Element {
	public var onHideDragEvent : (event: DragEvent, data: DragData) -> Void = null;
}

class DragAndDrop {
	static var currentDrag : DragData = null;
	static var currentDropTarget : DropTarget = null;
	static var dragOverlayHandler : js.html.Element = null;

	static public function makeDraggable(element: js.html.Element, onDrag : (event: DragEvent, data: DragData) -> Void) : Void {
		element.addEventListener("pointerdown", onInitialPointerDown, {capture: true});
		element.addEventListener("pointerup", onInitialPointerUp, {capture: true});
		var dragElement : DragElement = cast element;
		dragElement.onHideDragEvent = onDrag;
	}

	static var tmpDrag : DragData = new DragData(null);
	static public function makeDropTarget(element: js.html.Element, onEvent: (event: DropEvent, data: DragData) -> Void) : Void {
		var dropTarget : DropTarget = cast element;
		dropTarget.onHideDropEvent = onEvent;

		function nativeDropHandler(event: DropEvent, e: js.html.DragEvent) : Bool {
			tmpDrag.dropTargetValidity = AllowDrop;
			tmpDrag.data = [];
			var list = [];
			for (file in e.dataTransfer.files) {
				var fe = FileManager.inst.getFileEntry(untyped file.path);
				if (fe != null) {
					list.push(fe);
				}
			}
			tmpDrag.data.set("drag/filetree", list);
			tmpDrag.copyFromMouseEvent(e);
			onEvent(event, tmpDrag);
			if (tmpDrag.dropTargetValidity == ForbidDrop) {
				return false;
			}
			return true;
		}

		dropTarget.ondragenter = nativeDropHandler.bind(Enter);
		dropTarget.ondragleave = nativeDropHandler.bind(Leave);
		dropTarget.ondragover = nativeDropHandler.bind(Move);
		dropTarget.ondrop = nativeDropHandler.bind(Drop);
	}

	static function onInitialPointerDown(e:js.html.PointerEvent) : Void {
		if (e.button != 0)
			return;
		var element : js.html.Element = cast e.currentTarget;
		e.stopPropagation();
		element.addEventListener("pointermove", onInitialPointerMove, {capture: true});
		element.setPointerCapture(e.pointerId);
	}

	static function onInitialPointerUp(e:js.html.PointerEvent) : Void {
		var element : js.html.Element = cast e.currentTarget;
		if (currentDrag == null) {
			e.stopImmediatePropagation();
			e.stopPropagation();
			e.preventDefault();
			cleanupDrag(false);
			e.stopPropagation();
		}
	}

	static function onOverlayPointerMove(e: js.html.PointerEvent) : Void {
		currentDrag.copyFromMouseEvent(e);
		updateDragOperation();
	}

	static function updateDragOperation() : Void {
		var dropCandidates = js.Browser.document.elementsFromPoint(currentDrag.mouseX, currentDrag.mouseY);

		if (currentDrag.thumbnail != null) {
			if (currentDrag.thumbnail.parentElement == null)
				dragOverlayHandler.appendChild(currentDrag.thumbnail);
			var rect = currentDrag.thumbnail.getBoundingClientRect();
			currentDrag.thumbnail.style.left = '${currentDrag.mouseX - rect.width / 2}px';
			currentDrag.thumbnail.style.top = '${currentDrag.mouseY - rect.height + 4}px';
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

		currentDrag.dropTargetValidity = AllowDrop;
		currentDrag.setThumbnailVisiblity(true);

		if (currentDropTarget != null) {
			currentDropTarget.onHideDropEvent(Move, currentDrag);
		} else {
			currentDrag.dropTargetValidity = ForbidDrop;
		}

		// because we captured the pointer, the pointer is still considered over element, and so changing it's cursor
		// allow us to controll the appearance of the mouse pointer
		switch (currentDrag.dropTargetValidity) {
			case AllowDrop:
				dragOverlayHandler.style.cursor = "auto";
			case ForbidDrop:
				dragOverlayHandler.style.cursor = "no-drop";
		}
	}

	static function onOverlayPointerDown(e: js.html.PointerEvent) : Void {
		e.stopImmediatePropagation();
		e.stopPropagation();
		e.preventDefault();
		cleanupDrag(false);
	}

	static function onOverlayPointerUp(e: js.html.PointerEvent) : Void {
		e.stopImmediatePropagation();
		e.stopPropagation();
		e.preventDefault();
		cleanupDrag(e.button == 0);
	}

	static function onOverlayLostPointerCapture(e: js.html.PointerEvent) : Void {
		if (currentDrag != null) {
			e.stopImmediatePropagation();
			e.stopPropagation();
			e.preventDefault();
			cleanupDrag(false);
		}
	}

	static function onOverlayKeyDown(e: js.html.KeyboardEvent) : Void {
		if (e.key == "Escape") {
			e.stopImmediatePropagation();
			e.stopPropagation();
			e.preventDefault();
			cleanupDrag(false);
		}
	}

	static function onInitialPointerMove(e:js.html.PointerEvent) : Void {
		if (dragOverlayHandler != null) {
			cleanupDrag(false);
		}

		var element : DragElement = cast e.currentTarget;
		if (element.onHideDragEvent == null)
			throw "Element is not a valid DragElement";
		e.stopImmediatePropagation();
		e.stopPropagation();
		e.preventDefault();

		if (currentDrag == null) {

			currentDrag = new DragData(element);
			currentDrag.copyFromMouseEvent(e);
			element.onHideDragEvent(Start, currentDrag);
			if (currentDrag.canceled) {
				currentDrag = null;
				cleanupDrag(false);
				return;
			}

			dragOverlayHandler = js.Browser.document.createElement("fancy-drag-drop-overlay");
			js.Browser.document.body.appendChild(dragOverlayHandler);
			untyped dragOverlayHandler.popover = "manual";
			untyped dragOverlayHandler.showPopover();
			element.releasePointerCapture(e.pointerId);
			element.removeEventListener("pointermove", onInitialPointerMove);

			dragOverlayHandler.onpointermove = onOverlayPointerMove;
			js.Browser.window.addEventListener("scroll", updateDragOperation, {capture: true});
			js.Browser.window.addEventListener("keydown", onOverlayKeyDown, {capture: true});
			js.Browser.window.addEventListener("pointerdown", onOverlayPointerDown, {capture: true});
			js.Browser.window.addEventListener("pointerup", onOverlayPointerUp, {capture: true});
			js.Browser.window.addEventListener("contextmenu", onOverlayPointerDown, {capture: true});
			dragOverlayHandler.onlostpointercapture = onOverlayLostPointerCapture;
			dragOverlayHandler.setPointerCapture(e.pointerId);

			currentDropTarget = null;

			onOverlayPointerMove(e);
		}
	}

	static function cleanupDrag(performDrop: Bool) : Void {
		if (dragOverlayHandler != null) {
			dragOverlayHandler.remove();
			dragOverlayHandler = null;
		}

		js.Browser.window.removeEventListener("scroll", updateDragOperation, {capture: true});
		js.Browser.window.removeEventListener("keydown", onOverlayKeyDown, {capture: true});
		js.Browser.window.removeEventListener("pointerdown", onOverlayPointerDown, {capture: true});
		js.Browser.window.removeEventListener("pointerup", onOverlayPointerUp, {capture: true});
		js.Browser.window.removeEventListener("contextmenu", onOverlayPointerDown, {capture: true});

		currentDropTarget?.onHideDropEvent(Leave, currentDrag);
		if (performDrop)
			currentDropTarget?.onHideDropEvent(Drop, currentDrag);
		currentDropTarget = null;
		if (currentDrag != null) {
			currentDrag.sourceElement.removeEventListener("pointermove", onInitialPointerMove, {capture: true});
			currentDrag?.dispose();
			currentDrag = null;
		}
	}

}