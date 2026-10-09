package electron;

class App {

	/** command line arguments, without the executable / app path and switches **/
	public static var argv(get, never) : Array<String>;
	/** directory where per-user data is stored **/
	public static var dataPath(get, never) : String;
	/** "hide" or "CDB" **/
	public static var name(get, never) : String;

	static var openListeners : Array<Array<String> -> Void>;
	static var shortcuts : Map<String, Void -> Void>;

	static function get_argv() return Ipc.info.argv;
	static function get_dataPath() return Ipc.info.dataPath;
	static function get_name() return Ipc.info.name;

	/**
		Called with the command line arguments when the application is started again
		while already running, or when a file / url is opened from the OS.
	**/
	public static function onOpen( callb : Array<String> -> Void ) {
		if( openListeners == null ) {
			openListeners = [];
			Ipc.on("hide-app-open", function(_, args : Array<String>) {
				for( f in openListeners.copy() ) f(args);
			});
		}
		openListeners.push(callb);
	}

	public static function quit() {
		Ipc.call("app.quit");
	}

	public static function clearCache() {
		Ipc.call("app.clearCache");
	}

	public static function registerGlobalShortcut( accelerator : String, callb : Void -> Void ) {
		if( shortcuts == null ) {
			shortcuts = new Map();
			Ipc.on("hide-shortcut", function(_, accel : String) {
				var f = shortcuts.get(accel);
				if( f != null ) f();
			});
		}
		shortcuts.set(accelerator, callb);
		return (Ipc.call("shortcut.register", accelerator) : Bool);
	}

	public static function unregisterGlobalShortcut( accelerator : String ) {
		if( shortcuts == null || !shortcuts.exists(accelerator) ) return;
		shortcuts.remove(accelerator);
		Ipc.call("shortcut.unregister", accelerator);
	}

	/**
		Returns the full path of a File coming from a drag and drop or an input
	**/
	public static function getPathForFile( file : js.html.File ) : String {
		return Ipc.WebUtils.getPathForFile(file);
	}

	public static function setShared( value : Dynamic ) : Int {
		return Ipc.call("shared.set", value);
	}

	public static function getShared( id : Int ) : Dynamic {
		return Ipc.call("shared.get", id);
	}

}
