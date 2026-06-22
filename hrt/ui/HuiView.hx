package hrt.ui;

#if hui

class HuiView<T> extends HuiElement {
	var state : T;
	public var undo(default, never): hrt.tools.Undo = new hrt.tools.Undo();

	var hasUnsavedChanges(default, set): Bool = false;
	var toolbar : HuiToolbar;
	var errorMessage : Null<HuiErrorDisplay> = null;
	var suppressErrors: Bool = false;
	var currentException: Null<haxe.Exception> = null;
	var currentExceptionTime : Int = 0;

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

		undo.onAfterChange = () -> {
			hasUnsavedChanges = undo.isDirty();
		}

		registerCommand(HuiCommands.undo, FocusedView, () -> undo.undo());
		registerCommand(HuiCommands.redo, FocusedView, () -> undo.redo());
	}

	function setException(e: haxe.Exception) {
		if (suppressErrors)
			e = null;

		var isLoopError = false;

		// If an error was only present for one frame, keep it on screen
		if (e?.message != currentException?.message) {
			if (currentExceptionTime == 0) {
				e = currentException;
			} else {
				currentException = e;
				currentExceptionTime = 0;
			}
		}
		else {
			currentException = e;
			currentExceptionTime += 1;
			isLoopError = true;
		}

		dom.toggleClass("has-error", e != null);

		if (e == null) {
			errorMessage?.remove();
			errorMessage = null;
			return;
		}

		if (errorMessage == null) {
			errorMessage = new HuiErrorDisplay(this);
			errorMessage.addButton("Clear Error", () -> {currentException = null;});
		}
		if (currentExceptionTime == 1) {
			errorMessage.buttons.childElements[1].remove();
			errorMessage.addButton("Ignore Errors", () -> {suppressErrors = true; addSuppressErrorWarning();});
		}
		errorMessage.setError("Unhandled view exception", e);
	}

	final override function sync(ctx : h2d.RenderContext) {
		var exception : haxe.Exception = null;
		try {
			safeSync(ctx);
		} catch(e) {
			exception = e;
		}

		setException(exception);
	}

	function safeSync(ctx : h2d.RenderContext) {
		super.sync(ctx);
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

	function addSuppressErrorWarning() {
		var warn = new HuiSuppressedErrorsWarning(this);
		warn.showError.onClick = (e) -> {
			suppressErrors = false;
			warn.remove();
		}
	}

	function getToolbarWidgets() : Array<HuiElement> {
		return [];
	}


	function getContextMenuContent(content: Array<hrt.ui.HuiMenu.MenuItem>) {

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

class HuiSuppressedErrorsWarning extends HuiElement {
	static var SRC =
		<hui-suppressed-errors-warning>
			<hui-text("Warning : Errors are suppressed for this view")/>

			<hui-button public id="show-error">
				<hui-text("Show errors")/>
			</hui-button>
		</hui-suppressed-errors-warning>
}

#end