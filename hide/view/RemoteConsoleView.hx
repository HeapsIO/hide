package hide.view;

/**
	props.json configuration (all champs are optional):
	```json
	"remoteconsole": {
		"host": "127.0.0.1",
		"port": 40001,
		"disableAutoStartServer": false,
		"commands": [
			"hashlink",
			"custom"
		]
	},
	```
 */
class RemoteConsoleView extends hide.ui.View<{}> {
	static var rcmd : hrt.impl.RemoteConsole;
	static var statusBarIcon : Element;
	static var inst : RemoteConsoleView;
	var panels : Array<RemoteConsolePanel>;
	var panelsView : Element;
	var newPanelBtn : Element;

	public function new( ?state ) {
		super(state);
		panels = [];
		inst = this;
	}

	override function onDisplay() {
		var pconfig = config.get("remoteconsole");
		var host = pconfig?.host ?? hrt.impl.RemoteConsole.DEFAULT_HOST;
		var port = pconfig?.port ?? hrt.impl.RemoteConsole.DEFAULT_PORT;
		new Element('
		<div class="remoteconsole hide-scroll">
			<div class="connect">
				<input type="button" id="startServerBtn" value="Start Server"/>
				<input type="button" id="stopServerBtn" value="Stop Server"/>
				<label for="connectHost">Host IP</label>
				<input type="text" id="connectHost" value="$host:$port" disabled/>
			</div>
		</div>').appendTo(element);
		element.find("#startServerBtn").on('click', function(e) {
			startServer(port, host);
		});
		element.find("#stopServerBtn").on('click', function(e) {
			stopServer();
		});
		panelsView = element.find(".remoteconsole");
		for( panel in panels ) {
			panel.element.appendTo(panelsView);
		}
		if( rcmd != null ) {
			for( c in rcmd.connections ) {
				addPanel(c);
			}
		}
		if( panels.length <= 0 )
			addPanel();
	}

	override function onBeforeClose():Bool {
		forceClear();
		return super.onBeforeClose();
	}

	override function getTitle() {
		return "Remote console";
	}

	function forceClear() {
		for( p in panels ) {
			p.close(false);
		}
		panels = [];
		if( panelsView != null )
			panelsView.remove();
		panelsView = null;
		inst = null;
	}

	function refreshNewPanelButton() {
		if( newPanelBtn != null )
			newPanelBtn.remove();
		newPanelBtn = new Element('
		<div class="remoteconsole-panel new-panel">
			<i class="ico ico-plus"></i>
		</div>').appendTo(panelsView);
		newPanelBtn.on('click', function(e) {
			addPanel();
		});
	}

	function addPanel( ?c : hrt.impl.RemoteConsole.RemoteConsoleConnection ) {
		var panel = null;
		if( c != null ) {
			// Find the first empty or disconnected panel
			for( p in panels ) {
				if( p.connection == null || p.connection == c || !p.connection.isConnected() ) {
					p.connection = c;
					panel = p;
					break;
				}
			}
		}
		if( panel == null ) {
			var pconfig = config.get("remoteconsole");
			var panel = new RemoteConsolePanel(this, c, pconfig?.commands);
			panel.element.appendTo(panelsView);
			panels.push(panel);
		}
		refreshNewPanelButton();
	}

	public function removePanel( p : RemoteConsolePanel ) {
		panels.remove(p);
		p.element.remove();
		p.close(true);
	}

	public static function refreshStatusIcon() {
		if( statusBarIcon == null ) {
			statusBarIcon = new Element('<div class="ico ico-dot-circle-o" style="cursor:default;"></div>');
			hide.Ide.inst.addStatusIcon(statusBarIcon);
		}
		if( rcmd == null ) {
			statusBarIcon.css("color", "darkgray");
			statusBarIcon.prop("title", "[Remote Console] Server not started");
		} else if( rcmd.isConnected() ) {
			statusBarIcon.css("color", "#009500");
			statusBarIcon.prop("title", "[Remote Console] Server active");
		} else {
			statusBarIcon.css("color", "#c10000");
			statusBarIcon.prop("title", "[Remote Console] Server stopped");
		}
		statusBarIcon.empty();
		statusBarIcon.append(new Element('<span> ${rcmd.connections.length}</span>'));
	}

	static function startServer( port, host ) {
		if( rcmd != null && rcmd.isConnected() )
			return;
		rcmd = new hrt.impl.RemoteConsole(port, host);
		rcmd.onClose = () -> refreshStatusIcon();
		rcmd.startServer(function(c) {
			if( inst != null )
				inst.addPanel(c);
			refreshStatusIcon();
		});
		refreshStatusIcon();
	}

	static function stopServer() {
		if( rcmd != null )
			rcmd.close();
	}

	public static function onBeforeReload() {
		stopServer();
	}

	// allow hide-plugin to send console command to connected game instances
	public static function runInRemoteConsole( cmd : String ) {
		rcmd?.sendCommand("runInConsole", { cmd : cmd });
	}

	// allow hide-plugin to add/modify game-specific hide command control
	public static var commandViews = new Map<String, Class<RemoteConsoleCommand>>();
	public static function registerCommandView( name : String, cl : Class<RemoteConsoleCommand> ) {
		commandViews.set(name, cl);
		return null;
	}

	static var _ = init();
	static function init() {
		hide.ui.View.register(RemoteConsoleView);
		function wait() {
			if( Ide.inst?.config?.project == null ) {
				haxe.Timer.delay(wait, 10);
				return;
			}
			var config = Ide.inst.config.project;
			var pconfig = config.get("remoteconsole");
			if( pconfig != null && pconfig.disableAutoStartServer != true ) {
				var host = pconfig.host ?? hrt.impl.RemoteConsole.DEFAULT_HOST;
				var port = pconfig.port ?? hrt.impl.RemoteConsole.DEFAULT_PORT;
				startServer(port, host);
			}
		}
		// Needs to wait a little on reload, otherwise the port might still be occupied.
		haxe.Timer.delay(wait, 100);
		return 0;
	}
}

class RemoteConsolePanel extends hide.comp.Component {
	var view : RemoteConsoleView;
	var statusIcon : Element;
	public var connection(default, set) : hrt.impl.RemoteConsole.RemoteConsoleConnection;
	public var peerPath(default, null) : String;
	public var peerCwd(default, null) : String;
	public function new( view : RemoteConsoleView, connection : Null<hrt.impl.RemoteConsole.RemoteConsoleConnection>, commands : Null<Array<String>> ) {
		super(null, null);
		this.view = view;
		element = new Element('
		<div class="remoteconsole-panel">
			<div class="controls">
				<div class="ico ico-dot-circle-o" id="statusIcon" style="cursor:default;"></div>
				<div class="ico ico-close" id="closeBtn" title="Close panel and its connection"></div>
			</div>
			<div class="info">
				<span>Peer Info</span>
				<input type="text" id="peerInfo" disabled/>
			</div>
			<div class="logs">
			</div>
			<div class="commands">
			</div>
		</div>
		');
		this.statusIcon = element.find("#statusIcon");
		this.connection = connection;
		element.find("#closeBtn").on('click', function(e) {
			view.removePanel(this);
		});
		var commandsList = commands ?? ["hashlink", "heaps", "custom"];
		for( name in commandsList )
			addCommandElement(name);
	}
	function set_connection( c ) {
		if( connection == c )
			return connection;
		peerPath = null;
		peerCwd = null;
		if( c != null ) {
			c.onClose = () -> refreshStatusIcon();
			c.log = (msg) -> log(msg);
			c.logError = (msg) -> log(msg, true);
			c.sendCommand("info", null, function(d) {
				peerPath = d?.programPath == null ? "???" : haxe.io.Path.normalize(d.programPath);
				var peerArgs = d?.args ?? [];
				peerCwd = d?.cwd == null ? null : haxe.io.Path.normalize(d.cwd);
				var peerArgsStr = (peerArgs.length == 0 ? "" : " " + peerArgs.join(" "));
				var peerId = haxe.io.Path.withoutDirectory(peerPath) + peerArgsStr;
				var peerIdFull = peerPath + peerArgsStr;
				var peerInfo = element.find("#peerInfo");
				peerInfo.val(peerId);
				peerInfo.prop("title", peerIdFull);
			});
		}
		if( connection != null ) {
			connection.onClose = () -> {};
			connection.log = (msg) -> {};
			connection.logError = (msg) -> {};
		}
		connection = c;
		refreshStatusIcon();
		return connection;
	}
	function addCommandElement( name : String ) {
		var c = RemoteConsoleView.commandViews.get(name);
		if( c == null ) {
			log('Cannot find command element $name', true);
			return;
		}
		var comp = Type.createInstance(c, [this]);
		comp.element.appendTo(element.find(".commands"));
	}
	function refreshStatusIcon() {
		RemoteConsoleView.refreshStatusIcon();
		if( statusIcon == null )
			return;
		if( connection == null ) {
			statusIcon.css("color", "darkgray");
			statusIcon.prop("title", "Not connected");
		} else if( connection.isConnected() ) {
			statusIcon.css("color", "#009500");
			statusIcon.prop("title", "Connected");
		} else {
			statusIcon.css("color", "#c10000");
			statusIcon.prop("title", "Disconnected");
		}
	}
	public function close( disconnect : Bool ) {
		if( disconnect && connection != null ) {
			connection.close();
			log("Disconnected");
		}
		connection = null;
	}
	public function isConnected() {
		return connection != null && connection.isConnected();
	}
	public function log( msg : String, error : Bool = false ) {
		var logsView = element.find(".logs");
		var el = new Element('<p>${StringTools.htmlEscape(msg)}</p>').appendTo(logsView);
		if( error )
			el.addClass("error");
		logsView.scrollTop(logsView.get(0).scrollHeight);
	}
	public function sendCommand( cmd : String, ?args : Dynamic, ?onResult : Dynamic -> Void ) {
		if( isConnected() )
			connection.sendCommand(cmd, args, onResult);
		else
			log("sendCommand not available: no connection.", true);
	}
}

class RemoteConsoleCommand extends hide.comp.Component {
	var panel : RemoteConsolePanel;
	public function new( panel : RemoteConsolePanel ) {
		super(null, null);
		this.panel = panel;
		element = new Element('<fieldset class="command"></fieldset>');
	}
}

class RemoteConsoleSubCommandDump extends hide.comp.Component {
	public var dumpFile : Element;
	public function new( panel : RemoteConsolePanel,
			doDump : (onResult:(file:String,?filedesc:String,?dir:String)->Void) -> Void,
			?doOpen : (file:String) -> Void, autoOpen : Bool = true,
			?onExport : (file:String) -> Void,
		) {
		super(null, null);
		element = new Element('<div class="sub-sub-command"></div>');
		var dumpBtn = new Element('<input type="button" value="Dump"/>').appendTo(element);
		dumpFile = new Element('<input type="text" class="dump-file" disabled/>').appendTo(element);
		var exportBtn = new Element('<div class="ico ico-floppy-o disable" title="Export"/>').appendTo(element);
		var openInExplorerBtn = new Element('<div class="ico ico-folder-open disable" title="Open in Explorer"/>').appendTo(element);
		var openBtn = doOpen == null ? null : new Element('<div class="ico ico-share-square-o disable" title="Open"/>').appendTo(element);
		dumpBtn.on('click', function(e) {
			doDump(function (file, ?filedesc, ?dir) {
				if( file == null )
					return;
				if( dir == null )
					dir = (panel.peerCwd ?? hide.Ide.inst.projectDir) + "/";
				if( !sys.FileSystem.exists(dir + file) ) {
					panel.log('File $file is not generated', true);
					return;
				}
				var msg = '${filedesc??"File"} saved to $file';
				if( openBtn != null && !autoOpen )
					msg += ", automatic open is disabled";
				panel.log(msg);
				dumpFile.val(dir + file);
				dumpFile.prop("title", dir + file);
				exportBtn.removeClass("disable");
				openInExplorerBtn.removeClass("disable");
				if( openBtn != null ) {
					openBtn.removeClass("disable");
					if( autoOpen )
						openBtn.click();
				}
			});
		});
		exportBtn.on('click', function(e) {
			var file = dumpFile.val();
			if( file.length > 0 && sys.FileSystem.exists(file) ) {
				try {
					var newfile = new haxe.io.Path(file);
					var now = DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S");
					newfile.file = newfile.file + "_" + now;
					sys.io.File.copy(file, newfile.toString());
					file = newfile.toString();
					panel.log('File saved to $file');
					dumpFile.val(file);
					dumpFile.prop("title", file);
					if( onExport != null )
						onExport(file);
				} catch( e ) {
					panel.log(e.message, true);
				}
			} else {
				panel.log('File $file does not exist', true);
			}
		});
		openInExplorerBtn.on('click', function(e) {
			var file = dumpFile.val();
			if( file.length > 0 && sys.FileSystem.exists(file) ) {
				hide.Ide.showFileInExplorer(file);
			} else {
				panel.log('File $file does not exist', true);
			}
		});
		openBtn?.on('click', function(e) {
			var file = dumpFile.val();
			if( file.length > 0 && sys.FileSystem.exists(file) ) {
				doOpen(file);
			} else {
				panel.log('File $file does not exist', true);
			}
		});
	}
}

class RemoteConsoleCommandHL extends RemoteConsoleCommand {
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>Hashlink</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command">
			<h5>GC</h5>
		</div>').appendTo(element);
		var gcBtn = new Element('<input type="button" value="Major"/>').appendTo(subcmd);
		gcBtn.on('click', function(e) {
			panel.sendCommand("gcMajor", null, function(r) {
				panel.log('Gc.major took ${r/1000} ms');
			});
		});
		var subcmd = new Element('<div class="sub-command">
			<h5>GC Memory</h5>
		</div>').appendTo(element);
		var dumpHlPath = null;
		var dump = new RemoteConsoleSubCommandDump(panel, function(onResult) {
			panel.sendCommand("dumpMemory", null, function(r) {
				dumpHlPath = panel.peerPath;
				onResult("hlmemory.dump", "GC memory dump");
			});
		}
		#if (hashlink >= "1.15.0")
		, function(file) {
			ide.open("hide.view.MemProfiler",{}, null, function(view) {
				var prof = Std.downcast(view, hide.view.MemProfiler);
				prof.hlPath = dumpHlPath;
				prof.dumpPaths = [file];
				prof.process();
			});
		}, false
		#end
		, function(file) {
			// keep a .hl on export
			var dir = (panel.peerCwd ?? hide.Ide.inst.projectDir) + "/";
			try {
				var newfile = new haxe.io.Path(file);
				var now = DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S");
				newfile.file = "hlmemory_" + now;
				newfile.ext = "hl";
				sys.io.File.copy(panel.peerPath, newfile.toString());
			} catch( e ) {
				panel.log(e.message, true);
			}
		}
		).element.appendTo(subcmd);
		var subcmd = new Element('<div class="sub-command">
			<h5>GC Live Objs</h5>
		</div>').appendTo(element);
		var liveClass = new Element('<input type="text" placeholder="Class path..."/>').appendTo(subcmd);
		var liveBtn = new Element('<input type="button" value="Count"/>').appendTo(subcmd);
		liveBtn.on('click', function(e) {
			var clname = liveClass.val();
			panel.sendCommand("liveObjects", { clname : clname }, function(r) {
				if( r >= 0 ) {
					panel.log('Live Objects of class $clname: count $r');
				}
			});
		});
		liveClass.keydown(function(e) {
			if( e.key == 'Enter' ) liveBtn.click();
		});
		var subcmd = new Element('<div class="sub-command">
			<h5>Prof CPU</h5>
		</div>').appendTo(element);
		var startBtn = new Element('<input type="button" value="Start"/>').appendTo(subcmd);
		startBtn.on('click', function(e) {
			panel.sendCommand("profCpu", { action : "start" }, function(r) {
				panel.log("CPU profiling started");
			});
		});
		var dump = new RemoteConsoleSubCommandDump(panel, function(onResult) {
			panel.sendCommand("profCpu", { action : "dump" }, function(r) {
				var dir = (panel.peerCwd ?? hide.Ide.inst.projectDir) + "/";
				var file = "hlprofile.dump";
				#if (hashlink >= "1.15.0")
				try {
					var outfile = "hlprofile.json";
					hlprof.ProfileGen.run([dir + file, "-o", dir + outfile]);
					file = outfile;
				} catch (e) {
					panel.log(e.message, true);
				}
				#else
				panel.log("Please use hlprof.ProfileGen to convert it to json, or compile hide with lib hashlink >= 1.15.0");
				#end
				onResult(file, "Profile dump");
			});
		}
		#if (hashlink >= "1.15.0")
		, function(file) {
			ide.open("hide.view.DevTools", { profileFilePath : file });
		}
		#end
		).element.appendTo(subcmd);
		var subcmd = new Element('<div class="sub-command">
			<h5>Prof Alloc</h5>
		</div>').appendTo(element);
		var startBtn = new Element('<input type="button" value="Start"/>').appendTo(subcmd);
		startBtn.on('click', function(e) {
			panel.sendCommand("profTrack", { action : "start" }, function(r) {
				panel.log("CPU alloc track started");
			});
		});
		var dump = new RemoteConsoleSubCommandDump(panel, function(onResult) {
			panel.sendCommand("profTrack", { action : "dump" }, function(r) {
				onResult("memprofCount.dump", "Profile alloc dump");
			});
		}, function(file) {
			ide.open("hide.view.Script", { path : file });
		}).element.appendTo(subcmd);
	}
	static var _ = RemoteConsoleView.registerCommandView("hashlink", RemoteConsoleCommandHL);
}

class RemoteConsoleCommandHeaps extends RemoteConsoleCommand {
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>Heaps</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command">
			<h5>GPU Alloc</h5>
		</div>').appendTo(element);
		var enableBtn = new Element('<input type="button" value="Enable"/>').appendTo(subcmd);
		enableBtn.on('click', function(e) {
			panel.sendCommand("dumpGpu", { action : "enable" }, function(r) {
				panel.log('h3d.impl.MemoryManager.enableTrackAlloc(true) called');
			});
		});
		var diableBtn = new Element('<input type="button" value="Disable"/>').appendTo(subcmd);
		diableBtn.on('click', function(e) {
			panel.sendCommand("dumpGpu", { action : "disable" }, function(r) {
				panel.log('h3d.impl.MemoryManager.enableTrackAlloc(false) called');
			});
		});
		var dump = new RemoteConsoleSubCommandDump(panel, function(onResult) {
			panel.sendCommand("dumpGpu", { action : "dump" }, function(r) {
				onResult(r < 0 ? null : "gpudump.txt", "GPU dump");
			});
		}, function(file) {
			ide.open("hide.view.Script", { path : file });
		}).element.appendTo(subcmd);
		var subcmd = new Element('<div class="sub-command">
			<h5>Scene Prof</h5>
		</div>').appendTo(element);
		var startBtn = new Element('<input type="button" value="Start"/>').appendTo(subcmd);
		startBtn.on('click', function(e) {
			panel.sendCommand("profScene", { action : "start" }, function(r) {
				if( r < 0 )
					return;
				panel.log("Scene prof started");
			});
		});
		var dump = new RemoteConsoleSubCommandDump(panel, function(onResult) {
			panel.sendCommand("profScene", { action : "dump" }, function(r) {
				onResult(r < 0 ? null : "sceneprof.json", "Scene prof");
			});
		}, function(file) {
			ide.open("hide.view.Script", { path : file });
		}).element.appendTo(subcmd);
		var subcmd = new Element('<div class="sub-command">
			<h5>Res</h5>
		</div>').appendTo(element);
		var buildFilesBtn = new Element('<input type="button" value="Build Files"/>').appendTo(subcmd);
		buildFilesBtn.on('click', function(e) {
			panel.sendCommand("buildFiles", null, function(r) {
				panel.log('Build files done, $r directory/files processed');
			});
		});
	}
	static var _ = RemoteConsoleView.registerCommandView("heaps", RemoteConsoleCommandHeaps);
}

class RemoteConsoleCommandCustom extends RemoteConsoleCommand {
	var newCustomCommandBtn : Element;
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>Custom</legend>').appendTo(element);
		addRawCmd();
		addConsoleCmd();
		refreshNewCustomCommandButton();
	}
	function refreshNewCustomCommandButton() {
		if( newCustomCommandBtn != null )
			newCustomCommandBtn.remove();
		newCustomCommandBtn = new Element('
		<div class="sub-command">
			<div class="sub-sub-command" id="add-raw" title="Add raw custom command">
				<i class="ico ico-plus"></i>
				raw
			</div>
			<div class="sub-sub-command" id="add-console" title="Add console command">
				<i class="ico ico-plus"></i>
				console
			</div>
		</div>').appendTo(element);
		newCustomCommandBtn.find("#add-raw").on('click', function(e) {
			addRawCmd();
			refreshNewCustomCommandButton();
		});
		newCustomCommandBtn.find("#add-console").on('click', function(e) {
			addConsoleCmd();
			refreshNewCustomCommandButton();
		});
	}
	function addRawCmd() {
		var subcmd = new Element('<div class="sub-command">
			<h5>Raw</h5>
		</div>').appendTo(element);
		var cmdTxt = new Element('<input type="text" placeholder="Cmd..."/>').appendTo(subcmd);
		var argsTxt = new Element('<input type="text" placeholder="Args..." title="Can accept formatted json object"/>').appendTo(subcmd);
		var cmdBtn = new Element('<input type="button" value="Run"/>').appendTo(subcmd);
		cmdBtn.on('click', function(e) {
			var str : String = argsTxt.val();
			var obj = try {haxe.Json.parse(str); } catch (e) { str; };
			var cmdVal = cmdTxt.val();
			panel.sendCommand(cmdVal, obj, function(r) {
				panel.log('$cmdVal ${Std.string(obj)} result: $r');
			});
		});
		cmdTxt.keydown(function(e) {
			if( e.key == 'Enter' ) cmdBtn.click();
		});
		argsTxt.keydown(function(e) {
			if( e.key == 'Enter' ) cmdBtn.click();
		});
		var closeBtn = new Element('<i class="ico ico-close" title="Remove custom command"></i>').appendTo(subcmd);
		closeBtn.on('click', function(e) {
			subcmd.remove();
		});
	}
	function addConsoleCmd() {
		var subcmd = new Element('<div class="sub-command">
			<h5>Console</h5>
		</div>').appendTo(element);
		var cmdTxt = new Element('<input type="text" class="wide" placeholder="Console Cmd..."/>').appendTo(subcmd);
		var cmdBtn = new Element('<input type="button" value="Run"/>').appendTo(subcmd);
		cmdBtn.on('click', function(e) {
			var cmdVal = cmdTxt.val();
			panel.sendCommand("runInConsole", { cmd : cmdVal });
		});
		cmdTxt.keydown(function(e) {
			if( e.key == 'Enter' ) cmdBtn.click();
		});
		var closeBtn = new Element('<i class="ico ico-close" title="Remove console command"></i>').appendTo(subcmd);
		closeBtn.on('click', function(e) {
			subcmd.remove();
		});
	}
	static var _ = RemoteConsoleView.registerCommandView("custom", RemoteConsoleCommandCustom);
}
