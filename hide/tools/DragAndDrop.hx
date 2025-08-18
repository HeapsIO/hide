package hide.tools;

enum DragEvent {
	Start;
	Stop;
}

enum DropEvent {
	/**
		Called when the cursor has moved over a registered drop target
	**/
	Move;

	/**
		Called when the cursor stared hovering a registered drop target. Use it to update the style of the drop target to show that
		it can receive the drop for example.
	**/
	Enter;

	/**
		Called when the cursor stopped hovering the previously entered drop target. This event is always called when the drop operation
		ends (whenever it has been cancelled or processed). Use it to cleanup any style changes performed in the Move or Enter event for example.
	**/
	Leave;

	/**
		Called when the users perform a drop action on a registered valid drop target. Not called if a previous onDropEvent set dropTargetValidity to ForbidDrop
	**/
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
	/** Mouse position on the screen **/
	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	/**
		Whenever the shiftKey is being held down
	**/
	public var shiftKey : Bool = false;

	/**
		Custom data for the drag and drop operation. Set it up in the onDrag event handler, and read it in the onDropEvent
	**/
	public var data: Map<String, Dynamic> = [];
	public var sourceElement : DragElement = null;

	/** Allow to feedback to the user if the current drag operation has a valid target or no. Defaults to AllowDrop each time onDropEvent is called, so you'll need to set it to ForbidDrop if you want to prevent the operation each time**/
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
		container.appendChild(clone);
		thumbnail = container;
	}

	public function setThumbnailVisiblity(visible: Bool) : Void {
		if (thumbnail != null)
			thumbnail.style.visibility = visible ? "visible" : "hidden";
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
	static var currentDragElement: js.html.Element = null;
	static var currentDrag : DragData = null;
	static var currentDropTarget : DropTarget = null;
	static var dragOverlayHandler : js.html.Element = null;
	static var lastMouseX : Int = -1;
	static var lastMouseY : Int = -1;

	static public function makeDraggable(element: js.html.Element, onDragEvent : (event: DragEvent, data: DragData) -> Void) : Void {
		element.addEventListener("pointerdown", onInitialPointerDown);
		element.addEventListener("pointerup", onInitialPointerUp);

		var dragElement : DragElement = cast element;
		dragElement.onHideDragEvent = onDragEvent;
	}

	static var tmpDrag : DragData = new DragData(null);
	static public function makeDropTarget(element: js.html.Element, onDropEvent: (event: DropEvent, data: DragData) -> Void) : Void {
		var dropTarget : DropTarget = cast element;
		dropTarget.onHideDropEvent = onDropEvent;

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
			onDropEvent(event, tmpDrag);
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
		lastMouseX = e.clientX;
		lastMouseY = e.clientY;
		var element : js.html.Element = cast e.currentTarget;
		e.stopPropagation();

		currentDragElement = element;
		js.Browser.window.addEventListener("pointermove", onInitialPointerMove, {capture: true});
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

	static function onInitialPointerUp(e: js.html.PointerEvent) : Void {
		cleanupDrag(false);
	}

	static function onOverlayPointerUp(e: js.html.PointerEvent) : Void {
		e.stopImmediatePropagation();
		e.stopPropagation();
		e.preventDefault();
		cleanupDrag(e.button == 0 && currentDrag != null);
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
		if (lastMouseX < 0 || lastMouseX < 0 || hxd.Math.distance(e.clientX - lastMouseX, e.clientY - lastMouseY) < 5) {
			return;
		}

		if (dragOverlayHandler != null) {
			cleanupDrag(false);
		}

		var element : DragElement = cast currentDragElement;
		if (element.onHideDragEvent == null)
			throw "currentDragElement is not a valid DragElement";

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
			js.Browser.window.removeEventListener("pointermove", onInitialPointerMove, {capture: true});

			dragOverlayHandler.onpointermove = onOverlayPointerMove;
			js.Browser.window.addEventListener("scroll", updateDragOperation, {capture: true, passive: true});
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

		lastMouseX = -1;
		lastMouseY = -1;

		js.Browser.window.removeEventListener("pointermove", onInitialPointerMove, {capture: true});

		js.Browser.window.removeEventListener("scroll", updateDragOperation, {capture: true});
		js.Browser.window.removeEventListener("keydown", onOverlayKeyDown, {capture: true});
		js.Browser.window.removeEventListener("pointerdown", onOverlayPointerDown, {capture: true});
		js.Browser.window.removeEventListener("pointerup", onOverlayPointerUp, {capture: true});
		js.Browser.window.removeEventListener("contextmenu", onOverlayPointerDown, {capture: true});

		if (currentDropTarget != null && currentDropTarget.onHideDropEvent != null) {
			currentDropTarget.onHideDropEvent(Leave, currentDrag);
			if (performDrop) {
				currentDropTarget.onHideDropEvent(Drop, currentDrag);
			}
		}
		currentDropTarget = null;
		currentDragElement = null;

		if (currentDrag != null) {
			currentDrag?.dispose();
			currentDrag = null;
		}
	}

}