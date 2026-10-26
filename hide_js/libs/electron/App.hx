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

	/**
		Called in the main window when Chromium's GPU process is lost (TDR, driver crash),
		with Electron's details of the process (reason, exitCode)
	**/
	public static function onGpuCrash( callb : Dynamic -> Void ) {
		Ipc.on("hide-gpu-crash", (_, details) -> callb(details));
	}

	/**
		Zips `info` and this session's Chromium log, lost processes and crash dumps into a crash_report<date>.zip
		in the user data and shows it in the explorer. Resolved with the zip path.
	**/
	public static function createCrashReport( info : String ) : js.lib.Promise<String> {
		return cast Ipc.callAsync("app.createCrashReport", info);
	}

	/**
		True if a debugger (VSCode, DevTools) is attached to this window through --remote-debugging-port
	**/
	public static function isDebuggerAttached() : Bool {
		return Ipc.call("app.isDebuggerAttached");
	}

	/**
		Called when a debugger attaches to or detaches from this window
	**/
	public static function onDebuggerChange( callb : Bool -> Void ) {
		Ipc.on("hide-debugger", (_, attached : Bool) -> callb(attached));
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

}
