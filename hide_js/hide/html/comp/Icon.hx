package hide.html.comp;

import hide.html.WebComponent;

/**
	Monochrome icon `res/icons/svg2/<icon>.svg`, drawn with the text color.
**/
@:keep
class Icon extends WebComponent {
	static var observedAttributes = ["icon"];

	// The mask is on an inner element so that the host `style` attribute stays free
	var image : js.html.DivElement;

	public function new() {
		super();
		var root = attachShadow({mode: OPEN});
		root.adoptedStyleSheets = [styleSheet];
		image = js.Browser.document.createDivElement();
		root.append(image);
	}

	override public function attributeChangedCallback(name : String, oldValue : Null<String>, newValue : Null<String>) {
		if (newValue == null)
			image.style.removeProperty("mask-image");
		else
			image.style.setProperty("mask-image", 'url("res/$newValue")');
	}

	static var _ = register(Icon, "hide-icon");
}
