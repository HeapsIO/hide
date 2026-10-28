package hide.ui;

enum abstract DisplayPosition(String) from String to String {
	var Left = "content_left";
	var Center = "content_center";
	var Right = "content_right";
	var Bottom = "content_bottom";
}

typedef ViewOptions = { ?position : DisplayPosition, ?width : Int }

@:keepSub @:allow(hide.Ide) @:allow(hide.html.comp.TabViewContainer)
class View<T> extends hide.comp.Component {

	var container : hide.html.comp.TabViewContainer;
	public var fullScreen(get,set) : Bool;
	var contentWidth(get,never) : Int;
	var contentHeight(get,never) : Int;
	var watches : Array<{ keep : Bool, path : String, callb : Void -> Void }> = [];
	public var keys(get,null) : Keys;
	public var state(default, null) : T;
	public var undo(get, never) : hide.ui.UndoHistory;

	function get_undo() : hide.ui.UndoHistory {
		return undoStack[undoStack.length-1];
	}

	var undoStack: Array<UndoHistory> = [new hide.ui.UndoHistory()];

	public var config(get, null) : Config.ReadOnlyConfig;
	public var viewClass(get, never) : String;
	public var defaultOptions(get,never) : ViewOptions;
	var needRebuild : Bool;

	public function new(state:T) {
		super(null,null);
		element[0].classList.add("hide-view");
		(element[0] : Dynamic).__view = this;
		this.state = state;
		ide = Ide.inst;
		@:privateAccess ide.currentFullScreen = null;
	}

	public function watch( filePath : String, onChange : Void -> Void, ?opts : { ?checkDelete : Bool, ?keepOnRebuild : Bool } ) {
		if( opts == null ) opts = {};
		ide.fileWatcher.register(filePath, onChange, opts.checkDelete);
		var w = { keep : opts.keepOnRebuild, path : filePath, callb : onChange };
		watches.push(w);
		return w;
	}

	public function unwatch(w) {
		if( watches.remove(w) )
			ide.fileWatcher.unregister(w.path, w.callb);
	}

	function get_config() {
		if( config == null )
			config = ide.currentConfig;
		return config;
	}

	function get_keys() {
		if( keys == null ) {
			keys = new Keys(null);
			#if js
			keys.register("view.fullScreen", function() fullScreen = !fullScreen);
			keys.register("view.reopenLastClosedTab", function() ide.reopenLastClosedTab());
			#end
		}
		return keys;
	}

	public function getTitle() {
		return viewClass.split(".").pop();
	}

	public function onBeforeClose() {
		return true;
	}

	function get_viewClass() {
		return Type.getClassName(Type.getClass(this));
	}

	/**
		Push a new "UndoStack", that will collect all the new undo.change until
		popUndoStack is called
	**/
	public function pushUndoStack() {
		undoStack.push(new UndoHistory());
	}

	/**
		Pop the last pushUndoStack operation, creating a unique undo operation that contains all the changes were
		recorded in the undo buffer if any were created
	**/
	public function popUndoStack() {
		if (undoStack.length <= 1) {
			throw "trying to pop while there is only one or less undoes on the stack";
		}
		var top = undoStack.pop();

		@:privateAccess if (undo.undoElts.length > 0) {
			undo.change(top.toElement());
		}
	}

	public function setClipboard( v : Dynamic, ?type : String, ?opts : {} ) {
		electron.Clipboard.set(ide.toJSON({ type : type == null ? viewClass : type, value : v, opts : opts }));
	}

	public function hasClipboard( ?type : String ) {
		if( type == null ) type = viewClass;
		var v : Dynamic = try haxe.Json.parse(electron.Clipboard.get()) catch( e : Dynamic ) null;
		return v != null && v.type == type;
	}

	public function getClipboard( ?type : String, ?opts : { ref : Dynamic } ) : Dynamic {
		if( type == null ) type = viewClass;
		var v : Dynamic = try haxe.Json.parse(electron.Clipboard.get()) catch( e : Dynamic ) null;
		if( v != null && opts != null ) opts.ref = v.opts;
		return v == null || v.type != type ? null : v.value;
	}

	function syncTitle() {
		element[0].setAttribute("label", getTitle());
	}

	function isKeysLocked( e : js.jquery.Event ) {
		var active = js.Browser.document.activeElement;
		if( active == null || e.altKey )
			return false;
		if( e.ctrlKey && e.keyCode != "A".code && e.keyCode != "C".code && e.keyCode != "V".code && e.keyCode != "X".code )
			return false;
		if( active.nodeName == "TEXTAREA" )
			return true;
		if( active.nodeName == "INPUT" ) {
			var type = (""+active.getAttribute("type")).toLowerCase();
			if( type == "text" || type == "null" || type == "number" || type == "password" || type == "date" )
				return true;
		}
		return false;
	}

	public function processKeyEvent( e : js.jquery.Event ) {
		if( isKeysLocked(e) ) {
			e.stopPropagation();
			return true;
		}
		var active = js.Browser.document.activeElement;
		for( el in element.find("[haskeys=true]").add(element).elements() ) {
			if(el.has(active).length == 0 && el[0] != active)
				continue;
			var keys = hide.ui.Keys.get(el);
			if( keys == null ) continue;
			if( keys.processEvent(e,config) )
				return true;
		}
		// global keys
		return keys.processEvent(e,config);
	}

	/**
		Called once, when the view is first added to a container. Moving it to another container doesn't call it again.
	**/
	public function setContainer( cont : hide.html.comp.TabViewContainer ) {
		this.container = cont;
		@:privateAccess ide.views.push(this);
		syncTitle();
		element.keydown(function(e) {
			processKeyEvent(e);
		});
	}

	public final function rebuild() {
		function checkRebuild() {
			if( element == null || !needRebuild ) return;
			if( !isActive() ) {
				haxe.Timer.delay(checkRebuild,200);
				return;
			}
			needRebuild = false;
			onRebuild();
		}
		if( !needRebuild ) {
			needRebuild = true;
			checkRebuild();
		}
	}

	function onRebuild() {
		for( w in watches.copy() )
			if( !w.keep ) {
				ide.fileWatcher.unregister(w.path, w.callb);
				watches.remove(w);
			}
		undo.clear();
		syncTitle();

		// can happen on close all
		if (element == null)
			return;
		element.empty();
		element.off();
		onDisplay();
	}

	function onDisplay() {
		element.text(viewClass+(state == null ? "" : " "+state));
	}

	function onHide() {
	}

	public function onResize() {
	}

	public function onDrag(e : js.html.DragEvent) {
		return false;
	}

	public function onDragEnd(e : js.html.DragEvent) {
		return false;
	}

	public function onDrop(e : js.html.DragEvent) {
		return false;
	}

	function toString() {
		return Type.getClassName(Type.getClass(this)) + (this.state == null ? "" : "("+haxe.Json.stringify(this.state)+")");
	}

	function get_defaultOptions() return viewClasses.get(Type.getClassName(Type.getClass(this))).options;

	public function isActive() {
		return element != null && element[0].assignedSlot != null;
	}

	public function onActivate() {
	}

	/**
		Selects the view tab
	**/
	public function activate() {
		if( container != null )
			container.select(element[0]);
	}

	function saveState() {
		@:privateAccess ide.onLayoutChanged();
	}

	/**
		Returns false if `onBeforeClose` canceled it
	**/
	public function close() {
		if( container != null )
			return container.close(element[0]);
		if( element != null ) {
			element[0].remove();
			destroy();
		}
		return true;
	}

	function destroy() {
		hide.tools.CrashReport.log("close " + this);
		if( fullScreen )
			fullScreen = false;
		for( w in watches.copy() )
			ide.fileWatcher.unregister(w.path, w.callb);
		watches = [];
		@:privateAccess ide.views.remove(this);
		for( c in element.find("canvas") ) {
			var s : hide.comp.Scene = Reflect.field(c, "__scene");
			if( s != null )
				s.dispose();
		}
		(element[0] : Dynamic).__view = null;
		element = null;
		container = null;
		@:privateAccess ide.lastClosedTabStates.push(state);
	}

	function buildTabMenu() : Array<hrt.ui.HuiMenu.MenuItem> {
		return [
			{ label : "Close", click : close },
			{ label : "Close Others", click : function() for( v in @:privateAccess ide.views.copy() ) if( v != this && v.container == container ) v.close() },
			{ label : "Close All", click : function() for( v in @:privateAccess ide.views.copy() ) if( v.container == container ) v.close() },
		];
	}

	function get_contentWidth() return element[0].offsetWidth;
	function get_contentHeight() return element[0].offsetHeight;
	function get_fullScreen() return @:privateAccess ide.currentFullScreen == this;
	function set_fullScreen(v) {
		if( v )
			activate();
		if( v || fullScreen )
			@:privateAccess ide.currentFullScreen = v ? this : null;
		return v;
	}

	public static var viewClasses = new Map<String,{ name : String, cl : Class<View<Dynamic>>, options : ViewOptions }>();
	public static function register<T>( cl : Class<View<T>>, ?options : ViewOptions ) {
		var name = Type.getClassName(cl);
		if( options == null )
			options = {}
		if( options.position == null )
			options.position = Center;
		viewClasses.set(name, { name : name, cl : cl, options : options });
		return null;
	}

	static function createView( name : String, state : Dynamic ) : View<Dynamic> {
		return Type.createInstance(viewClasses.get(name).cl, [state]);
	}

}
