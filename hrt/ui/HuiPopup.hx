package hrt.ui;

#if hui

enum AnchorObject {
	Point(x: Float, y: Float);
	Element(element: HuiElement);
}

/**
				Anchors :
               +--------------------------------+
               |                                |
               +--------------------------------+
StartOutside<--|-->S   t   r   e    t   c   h<--|-->EndOutside
               |-->StartInside  |  EndInside <--|
			                 Middle
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

/**
	A floating element appearing above all other element in the scene.
	To add the popup to the ui, use uiBase.addPopup(popup)
**/
class HuiPopup extends HuiElement {
	static var SRC =
		<hui-popup>
		</hui-popup>

	public var anchor(default, set) : Anchor = {object: Point(0,0), directionX: EndOutside, directionY: EndOutside};

	final anchorMargin: Float = 4;
	var modal: HuiModalContainer = null;

	public var onCloseListeners : Array<Void -> Void> = [];
	var closed = false;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		onAfterReflow = onAfterReflowInternal;
	}

	/**
		Place the HuiPopup so it's anchored to the right/bottom of the given point
		If this causes the popup rectangle to go out of bound, the popup will try anchor
		itself to the left and/or top of the given point so it fits the screen
	**/
	public function set_anchor(v: Anchor) {
		anchor = v;
		needReflow = true;
		return v;
	}

	static function constraint(anchorDirection: AnchorDirection, anchorStart: Float, anchorEnd: Float, size: Float) : Float {
		switch(anchorDirection) {
			case StartOutside:
				return anchorStart - size;
			case StartInside:
				return anchorStart;
			case Middle:
				return anchorStart + (anchorEnd - anchorStart) / 2.0 - size / 2.0;
			case Stretch:
				return anchorStart;
			case EndInside:
				return anchorEnd - size;
			case EndOutside:
				return anchorEnd;
		}
	}

	static function fixAnchor(anchorDirection: AnchorDirection, pos: Float, size: Float, min: Float, max: Float) {
		switch (anchorDirection) {
			case StartOutside:
				if (pos < min)
					return EndOutside;
			case EndOutside:
				if (pos > max - size)
					return StartOutside;
			case StartInside:
				if (pos > max - size)
					return EndInside;
			case EndInside:
				if (pos < min)
					return StartInside;
			default:
		}
		return anchorDirection;
	}

	public function onAfterReflowInternal() {
		var left: Float;
		var top: Float;
		var down: Float;
		var right: Float;

		switch(anchor.object) {
			case Point(px,py):
				left = right = px;
				top = down = py;
			case Element(element):
				left = element.absX;
				right = element.absX + element.calculatedWidth;
				top = element.absY;
				down = element.absY + element.calculatedHeight;
		}

		var candidateX = constraint(anchor.directionX, left, right, calculatedWidth);
		var anchorX = fixAnchor(anchor.directionX, candidateX, calculatedWidth, 0, parentElement.calculatedWidth);
		x = constraint(anchorX, left, right, calculatedWidth);

		var candidateY = constraint(anchor.directionY, top, down, calculatedHeight);
		var anchorY = fixAnchor(anchor.directionY, candidateY, calculatedHeight, 0, parentElement.calculatedHeight);
		y = constraint(anchorY, top, down, calculatedHeight);
	}

	public function close() {
		remove();
	}

	override function onRemove() {
		if (!closed) {
			closed = true;
			for (onClose in onCloseListeners)
				onClose();
			onCloseListeners.resize(0);
		}
		super.onRemove();
	}


	/**
		Add popup in parent in a way that it can be close when the user clicks anywhere else. Return the created modal element
	**/
	function addDismissable(?parent: h2d.Object) : HuiModalContainer {
		modal = new HuiModalContainer(parent);
		modal.addChild(this);

		modal.onClick = (e: hxd.Event) -> {
			// We need to delay the closing of the
			// popup because it messes up with the input handling code
			// to remove interactibles from the scene in the middle of the event handling code
			hide.App.defer(() -> {
				close();
				modal.remove();
			});
		}

		modal.onKeyDown = onKeyDown;
		modal.onKeyUp = onKeyUp;
		modal.onTextInput = onTextInput;
		onCloseListeners.push(() -> modal.remove());

		return modal;
	}
}

#end