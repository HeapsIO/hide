package hrt.impl;

typedef RemotePrefabCallback = (data: Dynamic) -> Void;

/**
	A helper class to use a RemoteConsole in game.
 */
class RemoteTools {

	public static var RETRY_DELAY : Float = 2;

	static var rc : hrt.impl.RemoteConsole;
	static var mainEvent : haxe.MainLoop.MainEvent;
	static var lastUpdate : Float;
	static var onConnected : Bool -> Void;
	static var menuActions : Array<{ action : RemoteConsole.RemoteMenuAction, f : (id:String) -> Int}> = [];
	static var remotePrefabsCallbacks: Map<String, RemotePrefabCallback> = [];

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

	public static dynamic function onConsoleCommand( cmd : String ) : Int {
		logError('onConsoleCommand not implemented, received $cmd');
		return -1;
	}

	public static function registerCdbMenu( sheet : String, name : String, f : (id:String) -> Int ) {
		menuActions.push({ action : { name : name, cdbSheet: sheet }, f : f});
		// Send menuActions if already connected
		if( rc != null && rc.isConnected() ) {
			rc.sendCommand("registerMenuActions", { actions : [for( ma in menuActions ) ma.action] });
		}
	}

	static function onMenuAction( action : RemoteConsole.RemoteMenuAction, id : String ) : Int {
		if( action == null || id == null )
			return -1;
		for( ma in menuActions ) {
			if( ma.action.name == action.name && ma.action.cdbSheet == action.cdbSheet ) {
				return ma.f(id);
			}
		}
		return -1;
	}

	static function update() {
		if( rc == null || rc.isConnected() )
			return;
		var current = haxe.Timer.stamp();
		if( current - lastUpdate < RETRY_DELAY )
			return;
		lastUpdate = current;
		rc.connect(function(b) {
			if( onConnected != null )
				onConnected(b);
			if( b ) {
				var c = rc.connections[0];
				if( c != null ) {
					c.onConsoleCommand = (cmd) -> onConsoleCommand(cmd);
					c.onMenuAction = (action,id) -> onMenuAction(action,id);
				}
				// Send menuActions
				rc.sendCommand("registerMenuActions", { actions : [for( ma in menuActions ) ma.action] });
			}
		});
	}

	// ----- Commands -----

	public static function log( msg : String ) {
		rc?.sendCommand("log", msg);
	}

	public static function logError( msg : String ) {
		rc?.sendCommand("logError", msg);
	}

	/**
		@param selectExpr hscript expression that are used for select a line in the given sheet.
		Example: `$.id == Some_Unique_Id`, `$.name == SomeName`
		(`"` can be omitted in String literal when no ambiguity).
	 */
	public static function openCdb( sheet : String, ?line : Int, ?column : Int, ?selectExpr : String ) {
		rc?.sendCommand("open", { cdbsheet : sheet, line : line, column : column, selectExpr : selectExpr });
	}

	public static function openRes( file : String ) {
		rc?.sendCommand("open", { file : file });
	}

	public static function openDomkit( file : String, ?line : Int, ?column : Int ) {
		rc?.sendCommand("open", { file : file, line : line, column : column });
	}

	/**
		@param selectExpr hscript expression that are used for select some elements in the view.
		Example: `$.name == SomeName`, `$.props.id == Some_Unique_Id`
		(`"` can be omitted in String literal when no ambiguity).
	 */
	public static function openPrefab( file : String, ?selectExpr : String ) {
		rc?.sendCommand("open", { file : file, selectExpr : selectExpr });
	}

	public static function editPrefab( prefab: hrt.prefab.Prefab, id: String, callback: RemotePrefabCallback) {
		rc?.sendCommand("remotePrefab", {kind: hrt.impl.RemoteConsole.RemotePrefabActionKind.Open, data: @:privateAccess prefab.serialize(), id: id});
		remotePrefabsCallbacks.set(id, callback);
	}

	public static function makeSignature(data: String) {
		return haxe.crypto.Md5.encode(data);
	}
}
