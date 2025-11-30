package hrt.impl;

typedef RemoteMenuAction = {
	name : String,
	?cdbSheet : String,
}

typedef RemotePrefabAction = {
	kind: RemotePrefabActionKind,
	data: Dynamic,
	id: String,
};

enum abstract RemotePrefabActionKind(String) {
	var Open; /** Game -> Hide : Request open of the prefab data contained in data**/
	var Update; /** Hide -> Game : Update the opened prefab in the game with the new provided data**/
}

/**
	A simple socket-based local communication channel (plaintext and unsafe),
	aim at communicate between 2 programs (e.g. Hide and a HL game).

	Usage in game (see also hrt.impl.RemoteTools):
	```haxe
	var rcmd = new hrt.impl.RemoteConsole();
	// rcmd.log = (msg) -> logToUI(msg);
	// rcmd.logError = (msg) -> logErrorToUI(msg);
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
		this.connections = [];
	}

	public function startServer( ?onClient : RemoteConsoleConnection -> Void ) {
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
		// prevent remove during iteration by c.close
		var prevConnections = connections;
		connections = [];
		for( c in prevConnections ) {
			c.close();
		}
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
			for( c in connections ) {
				c.sendCommand(cmd, args, onResult);
			}
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
	var commands : Map<String, (args:Dynamic, onDone:Dynamic->Void) -> Void> = [];

	public function new( parent : RemoteConsole, s : hxd.net.Socket ) {
		this.parent = parent;
		this.sock = s;
		registerCommands(this);
	}

	public function close() {
		UID = 0;
		waitReply = [];
		commands = [];
		if( sock != null )
			sock.close();
		sock = null;
		if( parent != null )
			parent.connections.remove(this);
		parent = null;
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
		if( sock == null )
			return;
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

	/**
		Register a single command `name`, with `f` as command handler.
		`args` can be null, or an object that can be parsed from/to json.
		`onDone(result)` must be called when `f` finishes, and `result` can be null or a json serializable object.

		If `f` is `null`, the command is considered removed.
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

	@cmd("logError") function logErrorCmd( args : Dynamic ) {
		logError("[>] " + args);
	}

	function sendLog( msg : String ) {
		sendCommand("log", msg);
	}

	function sendLogError( msg : String ) {
		sendCommand("logError", msg);
	}

	@cmd function info() {
		return {
			programPath : Sys.programPath(),
			args : Sys.args(),
			cwd : Sys.getCwd(),
		};
	}

	// ----- Console ------

	@cmd function runInConsole( args : { cmd : String } ) : Int {
		return onConsoleCommand(args?.cmd ?? "");
	}

	public dynamic function onConsoleCommand( cmd : String ) : Int {
		sendLogError('onConsoleCommand not implemented, received $cmd');
		return -1;
	}

	public var menuActions(default, null) : Array<RemoteMenuAction> = null;
	@cmd function registerMenuActions( args : { actions : Array<RemoteMenuAction> } ) {
		menuActions = args?.actions;
	}

	@cmd function menuAction( args : { action : RemoteMenuAction, id : String } ) : Int {
		return onMenuAction(args?.action, args?.id);
	}

	public dynamic function onMenuAction( action : RemoteMenuAction, id : String ) : Int {
		sendLogError('onMenuAction not implemented');
		return -1;
	}

	@cmd function handleUri( path : String ) {
		onUri(path);
	}
	public dynamic function onUri( uri : String ) {
		sendLogError('onUri not implemented');
	}

	/**
		Game <-> Hide editor messages for remote prefab edition
	**/
	@cmd function remotePrefab(args: RemotePrefabAction) : {data: Dynamic} {
		switch (args.kind) {
			case Open:
				#if editor
				hide.Ide.inst.open("hide.view.Prefab", {remoteId: args.id}, null, (v) -> @:privateAccess {
					var prefabView : hide.view.Prefab = cast v;
					var toEdit = hrt.prefab.Prefab.createFromDynamic(args.data);
					prefabView.createData();
					toEdit.parent = prefabView.data;
					prefabView.sceneEditor.delayReady(() -> {
						prefabView.sceneEditor.setPrefab(cast prefabView.data);
						prefabView.sceneEditor.selectElements([toEdit], NoHistory);
						haxe.Timer.delay(() -> {
							prefabView.sceneEditor.focusObjects([toEdit.findFirstLocal3d()]);
						},0);
					});
				});
				#end
				return null;
			case Update:
				#if !editor
				var cb = @:privateAccess RemoteTools.remotePrefabsCallbacks.get(args.id);
				if (cb != null) {
					cb(args.data);
					return {data: "ok"};
				}
				return {data: null};
				#end
				return null;
		}
	}

#if editor
	// ----- Hide ------

	var parser : hscript.Parser;
	@cmd function open( args : { ?file : String, ?line : Int, ?column : Int, ?cdbsheet : String,
								?selectExpr : String } ) {
		if( args == null )
			return;
		if( parser == null ) {
			parser = new hscript.Parser();
			parser.identChars += "$";
		}
		if( args.cdbsheet != null ) {
			var sheet = hide.Ide.inst.database.getSheet(args.cdbsheet);
			hide.Ide.inst.open("hide.view.CdbTable", {}, null, function(view) {
				hide.Ide.inst.focus();
				var line = args.line;
				if( sheet != null && args.selectExpr != null ) {
					try {
						var expr = parser.parseString(args.selectExpr);
						for( i in 0...sheet.lines.length ) {
							if( evalExpr(sheet.lines[i], expr) == true ) {
								line = i;
								break;
							}
						}
					} catch( e ) {
						hide.Ide.inst.quickError(e);
					}
				}
				Std.downcast(view, hide.view.CdbTable).goto(sheet, line, args.column ?? -1);
			});
		} else if( args.file != null ) {
			hide.Ide.inst.showFileInResources(args.file);
			hide.Ide.inst.openFile(args.file, null, function(view) {
				hide.Ide.inst.focus();
				#if domkit
				var domkitView = Std.downcast(view, hide.view.DomkitStudio.DomkitLess);
				if( domkitView != null ) {
					var col = args.column ?? 0;
					var line = (args.line ?? 0) + 1;
					haxe.Timer.delay(function() @:privateAccess {
						var cssEditor = domkitView.editor;
						if (cssEditor != null) {
							cssEditor.focus();
							cssEditor.editor.revealLineInCenter(line);
							cssEditor.editor.setPosition({ column: col, lineNumber: line });
						}
					}, 1);
				}
				#end
				if( args.selectExpr != null ) {
					var sceneEditor : hide.comp.SceneEditor = null;
					var prefabView = Std.downcast(view, hide.view.Prefab);
					if( prefabView != null ) {
						sceneEditor = prefabView.sceneEditor;
					}
					var fxView = Std.downcast(view, hide.view.FXEditor);
					if( fxView != null ) {
						@:privateAccess sceneEditor = fxView.sceneEditor;
					}
					var modelView = Std.downcast(view, hide.view.Model);
					if( modelView != null ) {
						@:privateAccess sceneEditor = modelView.sceneEditor;
					}
					if( sceneEditor != null ) {
						try {
							var expr = parser.parseString(args.selectExpr);
							@:privateAccess var objs = sceneEditor.sceneData.findAll(null, function(o) {
								return evalExpr(o, expr);
							});
							sceneEditor.delayReady(() -> sceneEditor.selectElements(objs));
						} catch( e ) {
							hide.Ide.inst.quickError(e);
						}
					}
				}
			});
		}
	}

	function evalExpr( o : Dynamic, e : hscript.Expr ) : Dynamic {
		switch( e.e ) {
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			}
		case EIdent("$"):
			return o;
		case EIdent("null"):
			return null;
		case EIdent(v):
			return v; // Unknown ident, consider as a String literal
		case EField(e, f):
			var v = evalExpr(o, e);
			return Reflect.field(v, f);
		case EBinop(op, e1, e2):
			var v1 = evalExpr(o, e1);
			var v2 = evalExpr(o, e2);
			switch( op ) {
			case "==": return Reflect.compare(v1, v2) == 0;
			case "&&": return v1 == true && v2 == true;
			default:
				throw "Can't eval " + Std.string(v1) + " " + op + " " + Std.string(v2);
			}
		default:
			throw "Unsupported expression " + hscript.Printer.toString(e);
		}
	}
#end

#if hl
	// ----- Hashlink ------

	@cmd function gcMajor() : Int {
		var start = haxe.Timer.stamp();
		hl.Gc.major();
		var duration_us = (haxe.Timer.stamp() - start) * 1_000_000.;
		return Std.int(duration_us);
	}

	@cmd function dumpMemory( args : { file : String } ) {
		hl.Gc.major();
		hl.Gc.dumpMemory(args?.file);
		if( hxd.res.Resource.LIVE_UPDATE ) {
			var msg = "hxd.res.Resource.LIVE_UPDATE is on, you may want to disable it for mem dumps; RemoteConsole can also impact memdumps.";
			logError(msg);
			sendLogError(msg);
		}
	}

	@cmd function liveObjects( args : { clname : String } ) : Int {
		if( args == null || args.clname == null )
			return -1;
		#if( hl_ver >= version("1.15.0") && haxe_ver >= 5 )
		hl.Gc.major();
		var cl = std.Type.resolveClass(args.clname);
		if( cl == null ) {
			sendLogError('Failed to find class for ${args.clname}');
			return -1;
		}
		var c = hl.Gc.getLiveObjects(cl, 0);
		return c.count;
		#else
		sendLogError("getLiveObjects not supported, please use hl >= 1.15.0 and haxe >= 5.0.0");
		return -1;
		#end
	}

	@cmd function profCpu( args : { action : String, samples : Int, delay_ms : Int }, onDone : Dynamic -> Void ) {
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
				sendLogError('profCpu: action ${args?.action} not supported');
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

	@cmd function profTrack( args : { action : String } ) : Int {
		switch( args?.action ) {
		case "start":
			var tmp = hl.Profile.globalBits;
			tmp.set(Alloc);
			hl.Profile.globalBits = tmp;
			hl.Profile.reset();
		case "dump":
			hl.Profile.dump("memprofSize.dump", true, false);
			hl.Profile.dump("memprofCount.dump", false, true);
		default:
			sendLogError('Action ${args?.action} not supported');
			return -1;
		}
		return 0;
	}

	// ----- Heaps ------

	@cmd function dumpGpu( args : { action : String } ) : Int {
		switch( args?.action ) {
		case "enable":
			h3d.impl.MemoryManager.enableTrackAlloc(true);
		case "disable":
			h3d.impl.MemoryManager.enableTrackAlloc(false);
		case "dump":
			var engine = h3d.Engine.getCurrent();
			if( engine == null ) {
				sendLogError("h3d.Engine.getCurrent() == null");
				return -1;
			}
			var stats = engine.mem.allocStats();
			if( stats.length <= 0 ) {
				var msg = "No alloc found, enable with h3d.impl.MemoryManager.enableTrackAlloc()";
				sendLogError(msg);
				return -2;
			}
			var sb = new StringBuf();
			stats.sort((s1, s2) -> (s1.size > s2.size && s2.size > 0) ? -1 : 1);
			var total = 0;
			var textureSize = 0;
			var bufferSize = 0;
			for( s in stats ) {
				var size = Std.int(s.size / 1024);
				total += size;
				if ( s.tex )
					textureSize += size;
				else
					bufferSize += size;
				sb.add((s.tex?"Texture ":"Buffer ") + '${s.position} #${s.count} ${Std.int(s.size/1024)}kb\n');
			}
			sb.add('TOTAL: ${total}kb\n');
			sb.add('TEXTURE TOTAL: ${textureSize}kb\n');
			sb.add('BUFFER TOTAL: ${bufferSize}kb\n');
			sb.add('\nDETAILS\n');
			for(s in stats) {
				sb.add('${s.position} #${s.count} ${Std.int(s.size/1024)}kb\n');
				s.stacks.sort((s1, s2) -> (s1.size > s2.size && s2.size > 0) ? -1 : 1);
				for (stack in s.stacks) {
					sb.add('\t#${stack.count} ${Std.int(stack.size/1024)}kb ${stack.stack.split('\n').join('\n\t\t')}\n');
					for ( s in stack.stats )
						sb.add('\t\t${s.name} ${Std.int(s.size/1024)}kb\n');
				}
			}
			sys.io.File.saveContent("gpudump.txt", sb.toString());
		default:
			sendLogError('Action ${args?.action} not supported');
			return -1;
		}
		return 0;
	}

	@cmd function profScene( args : { action : String } ) : Int {
		#if sceneprof
		switch( args?.action ) {
		case "start":
			h3d.impl.SceneProf.start();
		case "dump":
			h3d.impl.SceneProf.stop();
			h3d.impl.SceneProf.save("sceneprof.json");
		default:
			sendLogError('Action ${args?.action} not supported');
			return -1;
		}
		return 0;
		#else
		sendLogError("SceneProf not supported, please compile with -D sceneprof");
		return -1;
		#end
	}

	@cmd function buildFiles( onDone : Int -> Void ) {
		sendLog("Build files begin");
		BuildTools.buildAllFiles( null, null, null, function(count, errCount) {
			if( errCount > 0 ) {
				sendLogError('Build files has $errCount errors, please check game log for more details');
			}
			onDone(count);
		});
	}

#end
}
