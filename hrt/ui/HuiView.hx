package hrt.ui;

#if hui

class HuiView<T> extends HuiElement {
	var state : T;
	public var undo(default, never): hrt.tools.Undo = new hrt.tools.Undo();

	function new(state: Dynamic, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		this.state = cast state ?? {};

		registerCommand(HuiCommands.undo, ElementAndChildren, () -> undo.undo());
		registerCommand(HuiCommands.redo, ElementAndChildren, () -> undo.redo());
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

	function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {

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

	public function getTypeName() {
		var cl = Type.getClass(this);
		for (name => otherCl in REGISTRY) {
			if (otherCl == cl)
				return name;
		}
		throw "unregistred view " + cl;
	}
}

#end