package hide.view;

/**
	props.json configuration (all champs are optional):
	```json
	"remoteconsole": {
		"host": "127.0.0.1",
		"port": 40001,
		"disableAutoStartServer": false,
		"commands": [
			"dump",
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
		var commandsList = commands ?? ["dump", "prof", "custom"];
		for( name in commandsList )
			addCommandElement(name);
	}
	function set_connection( c ) {
		if( connection == c )
			return connection;
		if( c != null ) {
			c.onClose = () -> refreshStatusIcon();
			c.log = (msg) -> log(msg);
			c.logError = (msg) -> log(msg, true);
			c.sendCommand("info", null, function(d) {
				peerPath = d?.programPath == null ? "???" : haxe.io.Path.normalize(d.programPath);
				var peerArgs = d?.args ?? [];
				peerCwd = d?.cwd == null ? null : haxe.io.Path.normalize(d.cwd);
				var peerId = peerPath + (peerArgs.length == 0 ? "" : " " + peerArgs.join(" "));
				element.find("#peerInfo").val(peerId);
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

class RemoteConsoleCommandDump extends RemoteConsoleCommand {
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>GC Memory</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var gcBtn = new Element('<input type="button" value="GC Major"/>').appendTo(subcmd);
		gcBtn.on('click', function(e) {
			panel.sendCommand("gcMajor", null, function(r) {
				panel.log('Gc.major took ${r/1000} ms');
			});
		});
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var dumpBtn = new Element('<input type="button" value="Dump"/>').appendTo(subcmd);
		var dumpFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		dumpBtn.on('click', function(e) {
			panel.sendCommand("dumpMemory", null, function(r) {
				var dir = (panel.peerCwd ?? hide.Ide.inst.projectDir) + "/";
				var file = "hlmemory.dump";
				try {
					var now = DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S");
					var outfile = "hlmemory_" + now;
					sys.FileSystem.rename(dir + file, dir + outfile + ".dump");
					file = outfile + ".dump";
					if( panel.peerPath != null && sys.FileSystem.exists(panel.peerPath) ) {
						sys.io.File.copy(panel.peerPath, dir + outfile + ".hl");
					}
				} catch( e ) {
					panel.log(e.message, true);
				}
				panel.log("Dump saved to " + file);
				dumpFile.val(dir + file);
			});
		});
		var openBtn = new Element('<input type="button" value="Open in Explorer"/>').appendTo(subcmd);
		openBtn.on('click', function(e) {
			var file = dumpFile.val();
			if( file.length > 0 && sys.FileSystem.exists(file) ) {
				hide.Ide.showFileInExplorer(file);
			} else {
				panel.log('File $file does not exist', true);
			}
		});
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var liveBtn = new Element('<input type="button" value="Live object"/>').appendTo(subcmd);
		var liveClass = new Element('<input type="text" placeholder="Class path..."/>').appendTo(subcmd);
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
	}
	static var _ = RemoteConsoleView.registerCommandView("dump", RemoteConsoleCommandDump);
}

class RemoteConsoleCommandProf extends RemoteConsoleCommand {
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>Profile</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var startBtn = new Element('<input type="button" value="Start"/>').appendTo(subcmd);
		startBtn.on('click', function(e) {
			panel.sendCommand("profCpu", { action : "start" }, function(r) {
				panel.log("Profiling started");
			});
		});
		var dumpBtn = new Element('<input type="button" value="Dump"/>').appendTo(subcmd);
		var dumpFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		dumpBtn.on('click', function(e) {
			panel.sendCommand("profCpu", { action : "dump" }, function(r) {
				var dir = (panel.peerCwd ?? hide.Ide.inst.projectDir) + "/";
				var file = "hlprofile.dump";
				panel.log('Profil raw dump saved to $file');
				#if (hashlink >= "1.15.0")
				try {
					var outfile = "hlprofile.json";
					hlprof.ProfileGen.run([dir + file, "-o", dir + outfile]);
					panel.log('Profil converted dump saved to $outfile');
					file = outfile;
				} catch (e) {
					panel.log(e.message, true);
				}
				#else
				panel.log("Please use hlpro.ProfileGen to convert it to json, or compile hide with lib hashlink >= 1.15.0");
				#end
				dumpFile.val(dir + file);
			});
		});
		var openBtn = new Element('<input type="button" value="Open in Explorer"/>').appendTo(subcmd);
		openBtn.on('click', function(e) {
			var dumpfile = dumpFile.val();
			if( dumpfile.length > 0 && sys.FileSystem.exists(dumpfile) ) {
				hide.Ide.showFileInExplorer(dumpfile);
			} else {
				panel.log('File $dumpfile does not exist', true);
			}
		});
	}
	static var _ = RemoteConsoleView.registerCommandView("prof", RemoteConsoleCommandProf);
}

class RemoteConsoleCommandCustom extends RemoteConsoleCommand {
	var newCustomCommandBtn : Element;
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>Custom</legend>').appendTo(element);
		addCustomCmd();
		refreshNewCustomCommandButton();
	}
	function refreshNewCustomCommandButton() {
		if( newCustomCommandBtn != null )
			newCustomCommandBtn.remove();
		newCustomCommandBtn = new Element('
		<div class="sub-command">
			<i class="ico ico-plus" title="Add custom command"></i>
		</div>').appendTo(element);
		newCustomCommandBtn.on('click', function(e) {
			addCustomCmd();
			refreshNewCustomCommandButton();
		});
	}
	function addCustomCmd() {
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var cmdTxt = new Element('<input type="text" placeholder="Cmd..."/>').appendTo(subcmd);
		var argsTxt = new Element('<input type="text" placeholder="Args..." title="Can accept formatted json object"/>').appendTo(subcmd);
		var cmdBtn = new Element('<input type="button" value="Run"/>').appendTo(subcmd);
		cmdBtn.on('click', function(e) {
			var str : String = argsTxt.val();
			var obj = try {haxe.Json.parse(str); } catch (e) { str; };
			var cmdVal = cmdTxt.val();
			panel.sendCommand(cmdVal, obj, (result) -> panel.log('$cmdVal $obj result: $result'));
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
	static var _ = RemoteConsoleView.registerCommandView("custom", RemoteConsoleCommandCustom);
}
