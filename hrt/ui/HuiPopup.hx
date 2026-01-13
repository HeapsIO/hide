package hrt.ui;

#if hui

/**
	A floating element appearing above all other element in the scene
**/
class HuiPopup extends HuiElement {
	static var SRC =
		<hui-popup>
		</hui-popup>

	var wantedAnchorX: Float = hxd.Math.NaN;
	var wantedAnchorY: Float = hxd.Math.NaN;

	final anchorMargin: Float = 4;


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
	public function setPositionAnchor(newX: Float, newY: Float) {
		wantedAnchorX = newX;
		wantedAnchorY = newY;
		needReflow = true;
	}

	public function onAfterReflowInternal() {
		if (!hxd.Math.isNaN(wantedAnchorX) && !hxd.Math.isNaN(wantedAnchorY)) {
			if (wantedAnchorX > parentElement.calculatedWidth - calculatedWidth - anchorMargin) {
				wantedAnchorX -= calculatedWidth;
			}
			if (wantedAnchorY > parentElement.calculatedHeight - calculatedHeight - anchorMargin) {
				wantedAnchorY -= calculatedHeight;
			}
			setPosition(wantedAnchorX, wantedAnchorY);
			wantedAnchorX = hxd.Math.NaN;
			wantedAnchorY = hxd.Math.NaN;
		}
	}

	public function close() {
		remove();
	}


	/**
		Add popup in parent in a way that it can be close when the user clicks anywhere else. Return the created modal element
	**/
	public function addDismissable(?parent: h2d.Object) : HuiModalContainer {
		var modal = new HuiModalContainer(parent);
		modal.addChild(this);

		modal.onClick = (e: hxd.Event) -> {
			e.cancel = true;
			e.propagate = true;

			// We need to delay the closing of the
			// popup because it messes up with the input handling code
			// to remove interactibles from the scene in the middle of the event handling code
			hide.App.defer(() -> {
				close();
				modal.remove();
			});
		}

		return modal;
	}
}

#end