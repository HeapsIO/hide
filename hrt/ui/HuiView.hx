package hrt.ui;

#if hui

class HuiView<T> extends HuiElement {
	var state : T;

	function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}

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

	override function getDisplayName() : String {
		return "unknown";
	};

	static var REGISTRY : Map<String, Class<HuiView<Dynamic>>> = [];
	public static function get(name: String) : Class<HuiView<Dynamic>> {
		return REGISTRY.get(name);
	}
	public static function register(name: String, cl: Class<HuiView<Dynamic>>) : Bool {
		REGISTRY.set(name, cl);
		return true;
	}
}

#end