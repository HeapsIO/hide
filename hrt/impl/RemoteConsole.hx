package hrt.impl;

/**
	A simple socket-based local communication channel,
	aim at communicate between 2 programs (e.g. Hide and a HL game).

	Usage in game:
	```haxe
	var rcmd = new hrt.impl.RemoteConsole();
	// rcmd.log = (msg) -> logToUI(msg);
	// rcmd.logError = (msg) -> logErrorToUI(msg);
	rcmd.registerCommands(handler);
	rcmd.connect();
	rcmd.sendCommand("log", "Hello!", function(r) {});
	```
 */
class RemoteConsole {
	public static var DEFAULT_HOST : String = "127.0.0.1";
	public static var DEFAULT_PORT : Int = 40001;
	public static var SILENT_CONNECT : Bool = true;

	public var host : String;
	public var port : Int;
	var sock : hxd.net.Socket;
	public var connections : Array<RemoteConsoleConnection>;

	public function new( ?port : Int, ?host : String ) {
		this.host = host ?? DEFAULT_HOST;
		this.port = port ?? DEFAULT_PORT;
	}

	public function startServer( ?onClient : RemoteConsoleConnection->Void ) {
		close();
		sock = new hxd.net.Socket();
		sock.onError = function(msg) {
			logError("Socket Error: " + msg);
			close();
		}
		sock.bind(host, port, function(s) {
			var connection = new RemoteConsoleConnection(this, s);
			connections.push(connection);
			s.onError = function(msg) {
				connection.logError("Client error: " + msg);
				connection.close();
				connection = null;
			}
			s.onData = () -> connection.handleOnData();
			if( onClient != null )
				onClient(connection);
			connection.log("Client connected");
		}, 1);
		log('Server started at $host:$port');
	}

	public function connect( ?onConnected : Bool -> Void ) {
		close();
		sock = new hxd.net.Socket();
		var connection = new RemoteConsoleConnection(this, sock);
		connections.push(connection);
		sock.onError = function(msg) {
			if( !SILENT_CONNECT )
				logError("Socket Error: " + msg);
			close();
			if( onConnected != null )
				onConnected(false);
		}
		sock.onData = () -> connection.handleOnData();
		sock.connect(host, port, function() {
			log("Connected to server");
			if( onConnected != null )
				onConnected(true);
		});
		if( !SILENT_CONNECT )
			log('Connecting to $host:$port');
	}

	public function close() {
		if( sock != null ) {
			sock.close();
			sock = null;
		}
		if( connections != null ) {
			for( s in connections )
				s.close();
		}
		connections = [];
		onClose();
	}

	public function isConnected() {
		return sock != null;
	}

	public dynamic function onClose() {
	}

	public dynamic function log( msg : String ) {
		trace(msg);
	}

	public dynamic function logError( msg : String ) {
		trace('[Error] $msg');
	}

	public function sendCommand( cmd : String, ?args : Dynamic, ?onResult : Dynamic -> Void ) {
		if( connections.length == 0 ) {
			// Ignore send when not really connected
		} else if( connections.length == 1 ) {
			connections[0].sendCommand(cmd, args, onResult);
		} else {
			logError("Send to multiple target not implemented");
		}
	}

}

@:keep
@:rtti
class RemoteConsoleConnection {

	var UID : Int = 0;
	var parent : RemoteConsole;
	var sock : hxd.net.Socket;
	var waitReply : Map<Int, Dynamic->Void> = [];

	public function new( parent : RemoteConsole, s : hxd.net.Socket ) {
		this.parent = parent;
		this.sock = s;
		registerCommands(this);
	}

	public function close() {
		UID = 0;
		waitReply = [];
		if( sock != null )
			sock.close();
		sock = null;
		parent.connections.remove(this);
		onClose();
	}

	public function isConnected() {
		return sock != null;
	}

	public dynamic function onClose() {
	}

	public dynamic function log( msg : String ) {
		trace(msg);
	}

	public dynamic function logError( msg : String ) {
		trace('[Error] $msg');
	}

	public function sendCommand( cmd : String, ?args : Dynamic, ?onResult : Dynamic -> Void ) {
		var id = ++UID;
		waitReply.set(id, onResult);
		sendData(cmd, args, id);
	}

	function sendData( cmd : String, args : Dynamic, id : Int ) {
		var obj = { cmd : cmd, args : args, id : id};
		var bytes = haxe.io.Bytes.ofString(haxe.Json.stringify(obj) + "\n");
		sock.out.writeBytes(bytes, 0, bytes.length);
	}

	public function handleOnData() {
		while( sock.input.available > 0 ) {
			var str = sock.input.readLine().toString();
			var obj = try { haxe.Json.parse(str); } catch (e) { logError("Parse error: " + e); null; };
			if( obj == null || obj.id == null ) {
				continue;
			}
			var id : Int = obj.id;
			if( id <= 0 ) {
				var onResult = waitReply.get(-id);
				waitReply.remove(-id);
				if( onResult != null ) {
					onResult(obj.args);
				}
			} else {
				onCommand(obj.cmd, obj.args, (result) -> sendData(null, result, -id));
			}
		}
	}

	function onCommand( cmd : String, args : Dynamic, onDone : Dynamic -> Void ) : Void {
		if( cmd == null )
			return;
		var command = commands.get(cmd);
		if( command == null ) {
			logError("Unsupported command " + cmd);
			return;
		}
		command(args, onDone);
	}

	// ----- Commands -----

	var commands = new Map<String, (args:Dynamic, onDone:Dynamic->Void) -> Void>();

	/**
		register a single command f.
		`args` can be null, or an object that can be parse from/to json.
		`onDone(result)` must be call when `f` finished, and `result` can be null or a json serializable object.
	 */
	public function registerCommand( name : String, f : (args:Dynamic, onDone:Dynamic->Void) -> Void ) {
		commands.set(name, f);
	}

	/**
		Register functions marked with `@cmd` in instance `o` as command handler (class of `o` needs `@:rtti` and `@:keep`).
		This is done with `Reflect` and `registerCommand`, `onDone` call are inserted automatically when necessary.
		Function name will be used as `cmd` key (and alias name if `@cmd("aliasname")`),
		if multiple function use the same name, only the latest registered is taken into account.

		Supported `@cmd` function signature:
		``` haxe
		@cmd function foo() : Dynamic {}
		@cmd function foo(args : Dynamic) : Dynamic {}
		@cmd function foo(onDone : Dynamic->Void) : Void {}
		@cmd function foo(args : Dynamic, onDone : Dynamic->Void) : Void {}
		```
	 */
	public function registerCommands( o : Dynamic ) {
		function regRec( cl : Dynamic ) {
			if( !haxe.rtti.Rtti.hasRtti(cl) )
				return;
			var rtti = haxe.rtti.Rtti.getRtti(cl);
			for( field in rtti.fields ) {
				var cmd = null;
				for( m in field.meta ) {
					if( m.name == "cmd" ) {
						cmd = m;
						break;
					}
				}
				if( cmd != null ) {
					switch( field.type ) {
						case CFunction(args, ret):
							var name = field.name;
							var func = Reflect.field(o, field.name);
							var f = null;
							if( args.length == 0 ) {
								f = (args, onDone) -> onDone(Reflect.callMethod(o, func, []));
							} else if( args.length == 1 && args[0].t.match(CFunction(_,_))) {
								f = (args, onDone) -> Reflect.callMethod(o, func, [onDone]);
							} else if( args.length == 1 ) {
								f = (args, onDone) -> onDone(Reflect.callMethod(o, func, [args]));
							} else if( args.length == 2 && args[1].t.match(CFunction(_,_)) ) {
								f = (args, onDone) -> Reflect.callMethod(o, func, [args, onDone]);
							} else {
								logError("Invalid @cmd, found: " + args);
								continue;
							}
							registerCommand(name, f);
							if( cmd.params.length == 1 ) {
								var alias = StringTools.trim(StringTools.replace(cmd.params[0], "\"", ""));
								registerCommand(alias, f);
							}
						default:
					}
				}
			}
		}
		var cl = Type.getClass(o);
		while( cl != null ) {
			regRec(cl);
			cl = Type.getSuperClass(cl);
		}
	}

	@cmd("log") function logCmd( args : Dynamic ) {
		log("[>] " + args);
	}

	@cmd function cwd() {
		return Sys.getCwd();
	}

	@cmd function programPath() {
		return Sys.programPath();
	}

#if editor
	@cmd function open( args : { file : String, line : Int, column : Int, cdbsheet : String } ) {
		if( args == null )
			return;
		if( args.cdbsheet != null ) {
			var sheet = hide.Ide.inst.database.getSheet(args.cdbsheet);
			hide.Ide.inst.open("hide.view.CdbTable", {}, function(view) {
				Std.downcast(view,hide.view.CdbTable).goto(sheet,args.line,args.column);
			});
		} else {
			hide.Ide.inst.showFileInResources(args.file);
			hide.Ide.inst.openFile(args.file);
		}
	}
#end

#if hl
	@cmd function dump( args : { file : String } ) {
		hl.Gc.major();
		hl.Gc.dumpMemory(args?.file);
		if( hxd.res.Resource.LIVE_UPDATE ) {
			var msg = "hxd.res.Resource.LIVE_UPDATE is on, you may want to disable it for mem dumps; RemoteConsole can also impact memdumps.";
			logError(msg);
			sendCommand("log", msg);
		}
	}

	@cmd function prof( args : { action : String, samples : Int, delay_ms : Int }, onDone : Dynamic -> Void ) {
		function doProf( args ) {
			switch( args.action ) {
			case "start":
				hl.Profile.event(-7, "" + (args.samples > 0 ? args.samples : 10000)); // setup
				hl.Profile.event(-3); // clear data
				hl.Profile.event(-5); // resume all
			case "resume":
				hl.Profile.event(-5); // resume all
			case "pause":
				hl.Profile.event(-4); // pause all
			case "dump":
				hl.Profile.event(-6); // save dump
				hl.Profile.event(-4); // pause all
				hl.Profile.event(-3); // clear data
			default:
				sendCommand("log", "Missing argument action for prof");
			}
		}
		if( args == null ) {
			onDone(null);
		} else if( args.delay_ms > 0 ) {
			haxe.Timer.delay(function() {
				doProf(args);
				onDone(null);
			}, args.delay_ms);
		} else {
			doProf(args);
			onDone(null);
		}
	}

#end
}
