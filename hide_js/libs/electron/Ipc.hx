package electron;

@:jsRequire("electron", "ipcRenderer")
private extern class IpcRenderer {
	static function sendSync( channel : String, cmd : String, args : haxe.extern.Rest<Dynamic> ) : Dynamic;
	static function send( channel : String, cmd : String, args : haxe.extern.Rest<Dynamic> ) : Void;
	static function invoke( channel : String, cmd : String, args : haxe.extern.Rest<Dynamic> ) : js.lib.Promise<Dynamic>;
	static function on( channel : String, listener : haxe.Constraints.Function ) : Void;
}

@:jsRequire("electron", "webUtils")
extern class WebUtils {
	static function getPathForFile( file : js.html.File ) : String;
}

typedef AppInfo = {
	var argv : Array<String>;
	var dataPath : String;
	var name : String;
	var windowId : Int;
	var version : String;
}

/**
	Communication with the Electron main process (bin/main.js)
**/
class Ipc {

	public static var info(get, null) : AppInfo;

	static function get_info() {
		if( info == null )
			info = send("hello");
		return info;
	}

	static function send( cmd : String, args : haxe.extern.Rest<Dynamic> ) : Dynamic {
		var r : Dynamic = IpcRenderer.sendSync("hide-sync", cmd, ...args);
		if( r == null )
			throw "IPC failure on " + cmd;
		if( r.error != null )
			throw r.error;
		return r.value;
	}

	/**
		Synchronous call to the main process, will block until the result is available.
	**/
	public static function call( cmd : String, args : haxe.extern.Rest<Dynamic> ) : Dynamic {
		if( info == null ) get_info();
		return send(cmd, ...args);
	}

	public static function callAsync( cmd : String, args : haxe.extern.Rest<Dynamic> ) : js.lib.Promise<Dynamic> {
		if( info == null ) get_info();
		return IpcRenderer.invoke("hide-async", cmd, ...args);
	}

	public static function on( channel : String, listener : haxe.Constraints.Function ) {
		IpcRenderer.on(channel, listener);
	}

}
