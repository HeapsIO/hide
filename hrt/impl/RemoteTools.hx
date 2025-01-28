package hrt.impl;

/**
	A helper class to use a RemoteConsole in game.
 */
class RemoteTools {

	public static var RETRY_DELAY : Float = 2;

	static var rc : hrt.impl.RemoteConsole;
	static var mainEvent : haxe.MainLoop.MainEvent;
	static var lastUpdate : Float;
	static var onConnected : Bool -> Void;

	public static function autoConnect( ?onConnected : Bool -> Void ) {
		RemoteTools.onConnected = onConnected;
		if( rc != null )
			return;
		var configdyn : Dynamic = null;
		if( hxd.res.Loader.currentInstance != null ) {
			var config = hxd.res.Loader.currentInstance.fs.get("props.json");
			configdyn = try haxe.Json.parse(config.getText()).remoteconsole catch( e : Dynamic ) null;
		} else {
			var config = try sys.io.File.getContent("res/props.json") catch( e : Dynamic ) null;
			configdyn = try haxe.Json.parse(config).remoteconsole catch( e : Dynamic ) null;
		}
		rc = new hrt.impl.RemoteConsole(configdyn?.port, configdyn?.host);
		mainEvent = haxe.MainLoop.add(update);
	}

	public static function stop() {
		if( mainEvent != null ) {
			mainEvent.stop();
		}
		mainEvent = null;
		if( rc != null ) {
			rc.close();
		}
		rc = null;
	}

	public static function isConnected() {
		return rc != null && rc.isConnected();
	}

	static function update() {
		if( rc == null || rc.isConnected() )
			return;
		var current = haxe.Timer.stamp();
		if( current - lastUpdate < RETRY_DELAY )
			return;
		lastUpdate = current;
		rc.connect(onConnected);
	}

	// ----- Commands -----

	public static function log( msg : String ) {
		rc?.sendCommand("log", msg);
	}

	public static function openCdb( sheet : String, ?line : Int, ?column : Int ) {
		rc?.sendCommand("open", { cdbsheet : sheet, line : line, column : column });
	}

	public static function openRes( file : String ) {
		rc?.sendCommand("open", { file : file });
	}

}
