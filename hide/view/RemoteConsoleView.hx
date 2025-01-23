package hide.view;

/**
	props.json configuration (all champs are optional):
	```json
	"remoteconsole": {
		"panels": [
			{
				"host": "127.0.0.2",
				"port": 40002,
				"commands": [
					"dump"
				]
			}
		]
	},
	```
 */
class RemoteConsoleView extends hide.ui.View<{}> {
	var panels : Array<RemoteConsolePanel>;
	var panelsView : Element;
	var newPanelBtn : Element;
	public var statusBarIcons : Element;

	public function new( ?state ) {
		super(state);
		panels = [];
	}

	override function onDisplay() {
		new Element('
		<div class="remoteconsole hide-scroll">
		</div>').appendTo(element);
		panelsView = element.find(".remoteconsole");
		statusBarIcons = new Element('<div></div>');
		hide.Ide.inst.addStatusIcon(statusBarIcons);
		addPanel();
	}

	override function onBeforeClose():Bool {
		var active = 0;
		for( p in panels ) {
			if( p.isConnected() )
				active++;
		}
		if( active > 0 && !hide.Ide.inst.confirm('Close console ($active connection(s) will be closed)?') )
			return false;
		forceClear();
		return super.onBeforeClose();
	}

	override function getTitle() {
		return "Remote console";
	}

	function forceClear() {
		for( p in panels ) {
			p.close();
		}
		panels = [];
		if( panelsView != null )
			panelsView.remove();
		panelsView = null;
		if( statusBarIcons != null )
			statusBarIcons.remove();
		statusBarIcons = null;
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

	function addPanel() {
		var pconfigs = config.get("remoteconsole")?.panels;
		var pconfig = pconfigs != null ? pconfigs[panels.length] : null;
		var panel = new RemoteConsolePanel(this, pconfig?.host, pconfig?.port, pconfig?.commands);
		panel.element.appendTo(panelsView);
		panels.push(panel);
		refreshNewPanelButton();
	}

	public function removePanel( p : RemoteConsolePanel ) {
		if( p.isConnected() ) {
			if( !hide.Ide.inst.confirm('Close console (connection will be closed)?') ) {
				return;
			}
		}
		panels.remove(p);
		p.element.remove();
		p.close();
	}

	// allow hide-plugin to add/modify game-specific hide command control
	public static var commandViews = new Map<String, Class<RemoteConsoleCommand>>();
	public static function registerCommandView( name : String, cl : Class<RemoteConsoleCommand> ) {
		commandViews.set(name, cl);
		return null;
	}

	static var _ = hide.ui.View.register(RemoteConsoleView);
}

class RemoteConsolePanel extends hide.comp.Component {
	var view : RemoteConsoleView;
	var statusBarIcon : Element;
	var statusIcon : Element;
	var handler : RemoteCommandHandler;
	var rcmd : hrt.impl.RemoteConsole;
	public function new( view : RemoteConsoleView, host : String, port : Int, commands : Array<String> ) {
		super(null, null);
		this.view = view;
		this.handler = new RemoteCommandHandler();
		element = new Element('
		<div class="remoteconsole-panel">
			<div class="controls">
				<div class="ico ico-dot-circle-o" id="statusIcon" style="color: darkgray; cursor:default;" title="Not connected"></div>
				<div class="ico ico-close" id="closeBtn" title="Close panel"></div>
			</div>
			<div class="connect">
				<input type="button" id="connectBtn" value="Connect"/>
				<input type="button" id="disconnectBtn" value="Disconnect"/>
				<label for="connectHost">Host</label>
				<input type="text" id="connectHost"/>
				<label for="connectPort">Port</label>
				<input type="text" id="connectPort" type="number"/>
			</div>
			<div class="logs">
			</div>
			<div class="commands">
			</div>
		</div>
		');

		this.statusBarIcon = new Element('
			<div class="ico ico-dot-circle-o" style="color: darkgray; cursor:default;" title="[Remote Console] Not connected"></div>'
		).appendTo(view.statusBarIcons);
		this.statusIcon = element.find("#statusIcon");

		element.find("#closeBtn").on('click', function(e) {
			this.statusBarIcon.remove();
			view.removePanel(this);
		});

		var connectHost = element.find("#connectHost");
		connectHost.val(host ?? hrt.impl.RemoteConsole.DEFAULT_HOST);
		function checkHost() {
			var host = connectHost.val();
			js.node.Dns.lookup(host, function(err, address, family) {
				if( err != null ) {
					log('Invalid host ($host): ${err.message}', true);
					return;
				}
				log('Host resolved ($host): $address');
				connectHost.val(address);
			});
		}
		connectHost.keydown(function(e) {
			if (e.key == 'Enter') checkHost();
		});
		connectHost.focusout(function(e) {
			checkHost();
		});

		var connectPort = element.find("#connectPort");
		connectPort.val(port ?? hrt.impl.RemoteConsole.DEFAULT_PORT);
		function checkPort() {
			var port = Std.int(connectPort.val());
			if( port < 0 )
				port = isConnected() ? rcmd.port : hrt.impl.RemoteConsole.DEFAULT_PORT;
			connectPort.val(port);
		}
		connectPort.keydown(function(e) {
			if (e.key == 'Enter') checkPort();
		});
		connectPort.focusout(function(e) {
			checkPort();
		});

		element.find("#connectBtn").on('click', function(e) {
			close();
			var host = element.find("#connectHost").val();
			var port = Std.parseInt(element.find("#connectPort").val());
			rcmd = new hrt.impl.RemoteConsole(port, host);
			rcmd.log = (msg) -> log(msg);
			rcmd.logError = (msg) -> log(msg, true);
			rcmd.registerCommands(handler);
			rcmd.connect(function(b) {
				refreshStatusIcon();
			});
		});

		element.find("#disconnectBtn").on('click', function(e) {
			close();
			refreshStatusIcon();
		});

		var commandsList = commands ?? ["dump", "prof", "custom"];
		for( name in commandsList )
			addCommandElement(name);
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
		if( isConnected() ) {
			statusBarIcon.css("color", "DarkGreen");
			statusBarIcon.prop("title", "[Remote console] Connected to " + rcmd.host + ":" + rcmd.port);
			statusIcon.css("color", "DarkGreen");
			statusIcon.prop("title", "Connected to " + rcmd.host + ":" + rcmd.port);
		} else {
			statusBarIcon.css("color", "#c10000");
			statusBarIcon.prop("title", "[Remote console] Disconnected");
			statusIcon.css("color", "#c10000");
			statusIcon.prop("title", "Disconnected");
		}
	}
	public function close() {
		if( rcmd != null ) {
			rcmd.close();
			log("Disconnected");
		}
		rcmd = null;
	}
	public function isConnected() {
		return rcmd != null && rcmd.isConnected();
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
			rcmd.sendCommand(cmd, args, onResult);
		else
			log("sendCommand not available: no connection.", true);
	}
}

@:keep
@:rtti
class RemoteCommandHandler {
	public function new() {
	}
	@cmd function open( args : { file : String, line : Int, column : Int, cdbsheet : String } ) {
		if( args == null )
			return;
		if( args.cdbsheet != null ) {
			var sheet = hide.Ide.inst.database.getSheet(args.cdbsheet);
			hide.Ide.inst.open("hide.view.CdbTable", {}, function(view) {
				Std.downcast(view,hide.view.CdbTable).goto(sheet,args.line,args.column);
			});
		} else {
			hide.Ide.inst.openFile(args.file);
		}
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
		new Element('<legend>Memory dump</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var dumpBtn = new Element('<input type="button" value="Dump"/>').appendTo(subcmd);
		var dumpFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		dumpBtn.on('click', function(e) {
			panel.sendCommand("dump", null, function(r) {
				panel.log("Dump saved to hlmemory.dump");
				dumpFile.val(hide.Ide.inst.projectDir + "/hlmemory.dump");
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
		var programBtn = new Element('<input type="button" value="Get program path"/>').appendTo(subcmd);
		var programFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		programBtn.on('click', function(e) {
			panel.sendCommand("programPath", null, function(r) {
				if( r != null ) {
					programFile.val(r);
				} else {
					panel.log("Unknown program path: " + r);
				}
			});
		});
		var openBtn = new Element('<input type="button" value="Open in Explorer"/>').appendTo(subcmd);
		openBtn.on('click', function(e) {
			var file = programFile.val();
			if( file.length > 0 && sys.FileSystem.exists(file) ) {
				hide.Ide.showFileInExplorer(file);
			} else {
				panel.log('File $file does not exist', true);
			}
		});
	}
	static var _ = RemoteConsoleView.registerCommandView("dump", RemoteConsoleCommandDump);
}

class RemoteConsoleCommandProf extends RemoteConsoleCommand {
	public function new( panel : RemoteConsolePanel ) {
		super(panel);
		new Element('<legend>CPU Profile</legend>').appendTo(element);
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var startBtn = new Element('<input type="button" value="Start"/>').appendTo(subcmd);
		startBtn.on('click', function(e) {
			panel.sendCommand("prof", { action : "start" }, function(r) {
				panel.log("Profiling started");
			});
		});
		var dumpBtn = new Element('<input type="button" value="Dump"/>').appendTo(subcmd);
		var dumpFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		dumpBtn.on('click', function(e) {
			panel.sendCommand("prof", { action : "dump" }, function(r) {
				panel.log("Profil raw dump saved to hlprofile.dump");
				dumpFile.val(hide.Ide.inst.projectDir + "/hlprofile.dump");
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
	#if (hashlink >= "1.15.0")
		var subcmd = new Element('<div class="sub-command"></div>').appendTo(element);
		var convertBtn = new Element('<input type="button" value="Convert"/>').appendTo(subcmd);
		var jsonFile = new Element('<input type="text" disabled/>').appendTo(subcmd);
		convertBtn.on('click', function(e) {
			var file = dumpFile.val();
			if( file.length < 0 )
				file = hide.Ide.inst.projectDir + "/hlprofile.dump";
			var outfile = hide.Ide.inst.projectDir + "/hlprofile.json";
			jsonFile.val(outfile);
			try {
				hlprof.ProfileGen.run([file, "-o", outfile]);
				panel.log("Profil converted dump saved to hlprofile.json");
			} catch (e) {
				panel.log(e.message, true);
			}
		});
		var openBtn = new Element('<input type="button" value="Open in Explorer"/>').appendTo(subcmd);
		openBtn.on('click', function(e) {
			var jsonfile = jsonFile.val();
			if( jsonfile.length > 0 && sys.FileSystem.exists(jsonfile) ) {
				hide.Ide.showFileInExplorer(jsonfile);
			} else {
				panel.log('File $jsonfile does not exist', true);
			}
		});
	#end
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
