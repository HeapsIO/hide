package electron;

typedef WindowOptions = {
	?show : Bool,
	?title : String,
	?width : Int,
	?height : Int,
}

/**
	Handle on an Electron BrowserWindow.

	Events : close, closed, maximize, minimize, restore, move, resize, focus, blur, show, hide,
	enter-fullscreen, leave-fullscreen.

	Listening to "close" on the current window prevents it from closing : `close(true)`
	must then be called to actually close it.
**/
class Window {

	static var windows : Map<Int, Window>;
	static var current : Window;

	public var id(default, null) : Int;
	public var x(get, never) : Int;
	public var y(get, never) : Int;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var title(get, set) : String;
	public var isMaximized(get, never) : Bool;
	/** only supported on the current window **/
	public var menu(default, set) : Menu;

	var listeners : Map<String, Array<Void -> Void>> = new Map();
	var menuItems : Map<String, MenuItem> = new Map();

	function new( id : Int ) {
		this.id = id;
	}

	function get_x() return getBounds().x;
	function get_y() return getBounds().y;
	function get_width() return getBounds().width;
	function get_height() return getBounds().height;
	function get_isMaximized() : Bool return Ipc.call("win.isMaximized", id);
	function get_title() : String return Ipc.call("win.getTitle", id);
	function set_title( t : String ) {
		Ipc.call("win.setTitle", id, t);
		return t;
	}

	public function getBounds() : Screen.Rect {
		return Ipc.call("win.getBounds", id);
	}

	function set_menu( m : Menu ) {
		if( this != get() ) throw "Can only set menu on current window";
		for( i in menuItems ) @:privateAccess i.attached = false;
		menuItems = new Map();
		Ipc.call("win.setMenu", m == null ? null : @:privateAccess m.toTemplate(menuItems));
		return menu = m;
	}

	public function on( event : String, callb : Void -> Void ) {
		var l = listeners.get(event);
		if( l == null ) {
			l = [];
			listeners.set(event, l);
			Ipc.call("win.subscribe", id, [event]);
		}
		l.push(callb);
	}

	function dispatch( event : String ) {
		var l = listeners.get(event);
		if( l == null ) return;
		for( f in l.copy() ) f();
	}

	public function showDevTools() Ipc.call("win.openDevTools", id);
	public function moveTo( x : Int, y : Int ) Ipc.call("win.moveTo", id, x, y);
	public function resizeTo( w : Int, h : Int ) Ipc.call("win.resizeTo", id, w, h);
	public function resizeBy( dw : Int, dh : Int ) Ipc.call("win.resizeBy", id, dw, dh);
	public function maximize() Ipc.call("win.maximize", id);
	public function minimize() Ipc.call("win.minimize", id);
	public function restore() Ipc.call("win.restore", id);
	public function enterFullscreen() Ipc.call("win.setFullScreen", id, true);
	public function leaveFullscreen() Ipc.call("win.setFullScreen", id, false);
	public function focus() Ipc.call("win.focus", id);
	public function blur() Ipc.call("win.blur", id);
	public function show( b = true ) Ipc.call("win.show", id, b);
	public function hide() Ipc.call("win.show", id, false);
	public function close( force = false ) Ipc.call("win.close", id, force);

	static function init() {
		if( windows != null ) return;
		windows = new Map();
		Ipc.on("hide-win-event", function(_, id : Int, event : String) {
			var w = windows.get(id);
			if( w == null ) return;
			w.dispatch(event);
			if( event == "closed" ) windows.remove(id);
		});
		Ipc.on("hide-menu-click", function(_, itemId : String) {
			var item = current == null ? null : current.menuItems.get(itemId);
			if( item != null ) item.click();
		});
	}

	static function getById( id : Int ) {
		init();
		var w = windows.get(id);
		if( w == null ) {
			w = new Window(id);
			windows.set(id, w);
		}
		return w;
	}

	/**
		The window of the current page
	**/
	public static function get() : Window {
		if( current == null ) current = getById(Ipc.info.windowId);
		return current;
	}

	public static function getAll() : Array<Window> {
		var all : Array<{ id : Int }> = Ipc.call("win.list");
		return [for( w in all ) getById(w.id)];
	}

	/**
		Open a new window, url is relative to the application directory
	**/
	public static function open( url : String, ?options : WindowOptions ) : Window {
		var id : Int = Ipc.call("win.open", url, options);
		return getById(id);
	}

	/**
		Call a function on the page that opened this window
	**/
	public static function callOpener( name : String, param : Dynamic ) {
		Ipc.call("win.callParent", name, param);
	}

	public static function onOpenerCall( callb : String -> Dynamic -> Void ) {
		Ipc.on("hide-parent-call", function(_, name : String, param : Dynamic) callb(name, param));
	}

}
