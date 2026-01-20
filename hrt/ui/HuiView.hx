package hrt.ui;

#if hui

class HuiView<StateType> extends HuiElement {
	var state : StateType;

	/**
		Called when the view becomes visible on the screen
	**/
	function onDisplay() {

	}

	/**
		Called when the views becomes no longer visible on screen
	**/
	function onHide() {

	}

	/**
		Called before the user closes the view
	**/
	function onClose() {

	}
}

#end