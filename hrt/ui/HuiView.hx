package hrt.ui;

#if hui

class HuiView<T> extends HuiElement {
	var state : T;
	public var undo(default, never): hrt.tools.Undo = new hrt.tools.Undo();

	var hasUnsavedChanges(default, set): Bool = false;
	var toolbar : HuiToolbar;

	function set_hasUnsavedChanges(v: Bool) {
		if (v != hasUnsavedChanges) {
			hasUnsavedChanges = v;
			onHasUnsavedChangesChanged();
		}
		return v;
	}

	public dynamic function onHasUnsavedChangesChanged() {};

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

	/**
		Request for this tab to be closed. The tab should call the callback with canClose to true if the tab can be closed, or false if the closure of the tab should be cancelled
	**/
	function requestClose(callback: (canClose: Bool) -> Void) {
		callback(true);
	}


	function buildToolbar() {
		if (toolbar == null) {
			toolbar = new HuiToolbar();
			addChildAt(toolbar, 0);
		}
		for (w in getToolbarWidgets())
			toolbar.addWidget(w);
	}

	function getToolbarWidgets() : Array<HuiElement> {
		return [];
	}


	function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {

	}

	final override function getDisplayName() : String {
		return getViewName() + (hasUnsavedChanges ? " *" : "");
	};

	function getViewName() : String {
		return "unknown";
	}

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