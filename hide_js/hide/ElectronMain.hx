package hide;

import electron.main.Electron;

typedef WindowState = {
	var interceptClose : Bool;
	var forceClose : Bool;
	var opener : Null<Int>;
	var menu : Menu;
}

typedef CreateWindowOptions = {
	?show : Bool,
	?title : String,
	?width : Int,
	?height : Int,
	?opener : Int,
}

/**
	Electron main process for HIDE / CDB, compiled to bin/main.js by hide.hxml (after --next).

	Renderer windows run hide.js with full Node integration and talk to this process
	through the "hide-sync" / "hide-async" IPC channels (see electron.Ipc).
**/
class ElectronMain {

	static var MIMES = ["text" => "text/plain", "html" => "text/html", "rtf" => "text/rtf", "png" => "image/png", "jpeg" => "image/jpeg"];

	static var isCDB : Bool;
	static var appName : String;
	static var appTitle : String;
	// HIDE_TEST=1 (automated testing) : replace alert/confirm popups by console logs, implies background
	static var testMode : Bool;
	// --background : never activate / focus / maximize windows so they stay behind the user's ones
	static var background : Bool;

	static var mainWindow : BrowserWindow;
	static var quitting = false;
	static var windowStates : Map<Int, WindowState> = new Map();
	static var sharedRefs : Map<Int, Dynamic> = new Map();
	static var sharedRefId = 0;
	// window id => subscriber webContents id => events
	static var subscriptions : Map<Int, Map<Int, Array<String>>> = new Map();
	// webContents id => accelerators
	static var shortcuts : Map<Int, Array<String>> = new Map();
	static var handlers : Map<String, haxe.Constraints.Function> = new Map();

	static function main() {
		var argv : Array<String> = js.Node.process.argv;
		var env = js.Node.process.env;
		isCDB = argv.indexOf("--cdb") >= 0 || env.get("HIDE_START_CDB") == "1" || js.node.Path.parse(js.Node.process.execPath).name.toLowerCase() == "cdb";
		testMode = env.get("HIDE_TEST") == "1";
		background = testMode || argv.indexOf("--background") >= 0;
		appName = isCDB ? "CDB" : "hide";
		appTitle = isCDB ? "CDB" : "HIDE";

		App.setName(appName);
		// --user-data-dir : separate instance (own profile and single instance lock)
		if( !App.commandLine.hasSwitch("user-data-dir") )
			App.setPath("userData", js.node.Path.join(App.getPath("appData"), appName));
		App.commandLine.appendSwitch("js-flags", "--expose-gc --no-efficiency-mode");
		// background : the windows stay behind the user's ones, they must still render (scroll, animation frames, timers, screenshots)
		App.commandLine.appendSwitch("disable-features", "AllowSoftwareGLFallbackDueToCrashes" + (background ? ",CalculateNativeWinOcclusion,IntensiveWakeUpThrottling" : ""));
		if( background ) {
			App.commandLine.appendSwitch("disable-renderer-backgrounding");
			App.commandLine.appendSwitch("disable-backgrounding-occluded-windows");
			App.commandLine.appendSwitch("disable-background-timer-throttling");
		}
		// DirectX 12 (jsdx) : Chromium must use the same GPU as the dx12 addon, shared textures can not cross adapters
		App.commandLine.appendSwitch("force_high_performance_gpu");
		App.commandLine.appendSwitch("ignore-gpu-blocklist");
		// after a GPU process loss (TDR, driver crash), WebGPU is recreated (dx.Display) : Chromium would block it
		// from the 2nd loss (3D APIs blocked for the page) and the 3rd (fallback to a GPU mode without it)
		App.commandLine.appendSwitch("disable-domain-blocking-for-3d-apis");
		App.commandLine.appendSwitch("disable-gpu-process-crash-limit");

		if( !App.requestSingleInstanceLock() ) {
			App.quit();
			return;
		}

		// leftover of the nw.js version, git can't remove it because of its untracked files
		js.Lib.require("fs").rm(js.node.Path.join(js.node.Path.dirname(js.Node.process.execPath), "package.nw"), { recursive : true, force : true }, (_) -> {});

		initCrashLogs();
		initHandlers();

		IpcMain.on("hide-sync", function(e : Dynamic, cmd : String, args : haxe.extern.Rest<Dynamic>) {
			function error( err : Dynamic ) {
				e.returnValue = { error : Std.string(err != null && err.stack != null ? err.stack : err) };
			}
			try {
				var r : Dynamic = runCommand(e.sender, cmd, args.toArray());
				if( Std.isOfType(r, js.lib.Promise) )
					(r : js.lib.Promise<Dynamic>).then((v) -> e.returnValue = { value : v }, error);
				else
					e.returnValue = { value : r };
			} catch( err : Dynamic ) {
				error(err);
			}
		});
		IpcMain.handle("hide-async", function(e : Dynamic, cmd : String, args : haxe.extern.Rest<Dynamic>) {
			return runCommand(e.sender, cmd, args.toArray());
		});

		App.on("second-instance", function(e, argv : Array<String>, cwd : String) {
			if( mainWindow == null || mainWindow.isDestroyed() ) return;
			if( mainWindow.isMinimized() ) mainWindow.restore();
			if( !background ) mainWindow.focus();
			send(mainWindow.webContents, "hide-app-open", filterArgv(argv, cwd));
		});
		App.on("open-file", function(e : Dynamic, file : String) {
			e.preventDefault();
			if( mainWindow != null ) send(mainWindow.webContents, "hide-app-open", [file]);
		});
		App.on("open-url", function(e : Dynamic, uri : String) {
			e.preventDefault();
			if( mainWindow != null ) send(mainWindow.webContents, "hide-app-open", [uri]);
		});
		App.on("before-quit", function() {
			quitting = true;
			for( s in windowStates ) s.forceClose = true;
		});
		App.on("window-all-closed", () -> App.quit());
		App.on("will-quit", () -> GlobalShortcut.unregisterAll());

		App.whenReady().then(function(_) {
			Menu.setApplicationMenu(null);
			try Session.defaultSession.setSpellCheckerLanguages(["en-US", "fr-FR"]) catch( e : Dynamic ) {}
			watchDebuggers();
			mainWindow = createWindow("app.html", {});
			mainWindow.on("closed", function() {
				mainWindow = null;
				App.quit();
			});
		});
	}

	// ---------------- helpers

	static function filterArgv( argv : Array<String>, ?cwd : String ) {
		var appPath = js.node.Path.resolve(App.getAppPath());
		var mainFile = js.node.Path.resolve(js.Node.__filename);
		if( cwd == null ) cwd = js.Node.process.cwd();
		var out = [];
		for( a in argv.slice(1) ) {
			if( StringTools.startsWith(a, "--project-dir=") || a == "--default-config" ) {
				out.push(a);
				continue;
			}
			if( StringTools.startsWith(a, "--") ) continue;
			var abs = js.node.Path.resolve(cwd, a);
			if( abs == appPath || abs == mainFile ) continue;
			out.push(sys.FileSystem.exists(abs) ? abs : a);
		}
		return out;
	}

	static function send( wc : WebContents, channel : String, args : haxe.extern.Rest<Dynamic> ) {
		if( wc != null && !wc.isDestroyed() ) wc.send(channel, ...args);
	}

	// ---------------- debuggers : CDP clients (VSCode, DevTools) attached to the pages

	// CDP target id => page
	static var cdpPages : Map<String, { url : String, attached : Bool }> = new Map();

	static function isDebuggerAttached( wc : WebContents ) {
		var url = wc.getURL();
		for( p in cdpPages )
			if( p.attached && p.url == url )
				return true;
		return false;
	}

	/** follows the pages of the --remote-debugging-port server, sends "hide-debugger" to the windows when a client attaches or detaches **/
	static function watchDebuggers() {
		var port = App.commandLine.getSwitchValue("remote-debugging-port");
		if( port == "" || port == "0" )
			return;
		js.Lib.global.fetch('http://127.0.0.1:$port/json/version').then((r) -> r.json()).then(function( v : Dynamic ) {
			var ws = new js.html.WebSocket(v.webSocketDebuggerUrl);
			ws.onopen = () -> ws.send(haxe.Json.stringify({ id : 1, method : "Target.setDiscoverTargets", params : { discover : true } }));
			ws.onmessage = function( m : js.html.MessageEvent ) {
				var msg : Dynamic = haxe.Json.parse(m.data);
				var info : Dynamic = msg.params?.targetInfo;
				if( msg.method == "Target.targetDestroyed" )
					cdpPages.remove(msg.params.targetId);
				if( info == null || info.type != "page" )
					return;
				var prev = cdpPages.get(info.targetId);
				cdpPages.set(info.targetId, { url : info.url, attached : info.attached });
				if( prev != null && prev.attached == info.attached && prev.url == info.url )
					return;
				for( w in BrowserWindow.getAllWindows() )
					if( w.webContents.getURL() == info.url )
						send(w.webContents, "hide-debugger", isDebuggerAttached(w.webContents));
			};
		}, (e) -> js.Browser.console.warn("Debugger watch failed : " + e));
	}

	// ---------------- crash reports : in the user data, zipped by createCrashReport

	// logs/logs_<date>_<time> in the user data
	static var sessionLogs : String;
	// logs/logs_thumb_<date>_<time> of the thumbnail generators of this session
	static var thumbLogs : Array<String> = [];

	/**
		Chromium's log (GPU process errors : device removed reasons...), the lost child processes,
		the DX12 device removals of the renderers (hide-dx12.log) and the crash dumps of all the processes, in a folder per session. The GPU process losses are shown by the main window.
		A .crashed file marks the sessions where a process crashed. The folders are deleted after two weeks.
	**/
	static function initCrashLogs() {
		function remove( path : String ) {
			try {
				if( sys.FileSystem.isDirectory(path) ) {
					for( f in sys.FileSystem.readDirectory(path) ) remove(js.node.Path.join(path, f));
					sys.FileSystem.deleteDirectory(path);
				} else
					sys.FileSystem.deleteFile(path);
			} catch( e : Dynamic ) {}
		}
		var logs = js.node.Path.join(App.getPath("userData"), "logs");
		if( sys.FileSystem.exists(logs) ) {
			var limit = Date.now().getTime() - 14 * 24 * 3600 * 1000.;
			for( f in sys.FileSystem.readDirectory(logs) ) {
				var path = js.node.Path.join(logs, f);
				if( sys.FileSystem.stat(path).mtime.getTime() < limit ) remove(path);
			}
		}
		sessionLogs = js.node.Path.join(logs, "logs_" + DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S"));
		sys.FileSystem.createDirectory(sessionLogs);
		// inherited by the renderers : the DX12 addon logs there (device removals)
		js.Node.process.env.set("HIDE_SESSION_LOGS", sessionLogs);
		// --enable-logging given on the command line (stderr when testing) : kept
		if( !App.commandLine.hasSwitch("enable-logging") ) {
			App.commandLine.appendSwitch("enable-logging", "file");
			App.commandLine.appendSwitch("log-file", js.node.Path.join(sessionLogs, "chromium.log"));
			// warnings and errors : the console messages of the pages are not logged
			App.commandLine.appendSwitch("log-level", "1");
		}
		App.setPath("crashDumps", js.node.Path.join(sessionLogs, "Crashpad"));
		CrashReporter.start({ uploadToServer : false });
		var crashed = false;
		function logGone( text : String, reason : String ) {
			js.node.Fs.appendFileSync(js.node.Path.join(sessionLogs, "process-gone.log"), DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S") + " " + text + "\n");
			if( reason != "clean-exit" && !crashed ) {
				crashed = true;
				js.node.Fs.writeFileSync(js.node.Path.join(sessionLogs, ".crashed"), "");
			}
		}
		App.on("child-process-gone", function(_, details : Dynamic) {
			logGone(details.type + " " + details.reason + ", exit code " + details.exitCode + (details.name != null ? " (" + details.name + ")" : ""), details.reason);
			if( details.type == "GPU" && details.reason != "clean-exit" && !quitting && mainWindow != null )
				send(mainWindow.webContents, "hide-gpu-crash", details);
		});
		App.on("render-process-gone", function(_, wc : WebContents, details : Dynamic) {
			logGone("renderer " + details.reason + ", exit code " + details.exitCode + " (" + wc.getURL() + ")", details.reason);
		});
	}

	/** zips the session logs, its crash dumps, `info` and the Windows GPU events in the user data, shows the zip in the explorer **/
	static function createCrashReport( info : String ) : js.lib.Promise<String> {
		// Windows version and the events of the last day : GPU driver (Display 4101 : driver reset by a TDR),
		// LiveKernelEvent reports (141 : TDR, its dump in LiveKernelReports/WATCHDOG, only readable as admin)
		function getWindowsInfo() {
			var os : Dynamic = js.Lib.require("os");
			var buf = new StringBuf();
			buf.add(os.version() + " " + os.release() + "\n");

			function query( log : String, filter : String ) : String {
				var q = '*[System[$filter and TimeCreated[timediff(@SystemTime) <= 86400000]]]';
				// written in the ANSI code page when redirected
				return try new js.html.TextDecoder("windows-1252").decode(cast js.node.ChildProcess.execSync('wevtutil qe $log "/q:$q" /f:text /rd:true /c:100', { timeout : 10000 })) catch( e : Dynamic ) "query failed : " + e + "\n";
			}
			buf.add("\nGPU driver events of the last 24 hours :\n");
			buf.add(query("System", "Provider[@Name='Display' or @Name='amdkmdag' or @Name='nvlddmkm' or @Name='igfx']"));

			buf.add("\nLiveKernelEvent reports of the last 24 hours :\n");
			for( e in query("Application", "Provider[@Name='Windows Error Reporting'] and (EventID=1001)").split("Event[") )
				if( e.indexOf("LiveKernelEvent") >= 0 )
					buf.add("Event[" + e);
			return buf.toString();
		}

		// "basic" right after a GPU process restart has no active device and no DX12 support.
		// "complete" can fail or never answer without a GPU process : "basic" then
		var timeout = new js.lib.Promise<Dynamic>((_, reject) -> haxe.Timer.delay(() -> reject("timeout"), 5000));
		var gpuInfo = js.lib.Promise.race([App.getGPUInfo("complete"), timeout]).catchError(_ -> App.getGPUInfo("basic"));
		return gpuInfo.then(function( gpu : Dynamic ) {
			var entries = new List<haxe.zip.Entry>();
			function add( name : String, data : js.node.Buffer, time : Date ) {
				var bytes = data.hxToBytes();
				var compressed = js.node.Zlib.deflateRawSync(data).hxToBytes();
				entries.add({ fileName : name, fileSize : bytes.length, fileTime : time, compressed : true, dataSize : compressed.length, data : compressed, crc32 : haxe.crypto.Crc32.make(bytes) });
			}
			function addDir( dir : String, prefix : String, ext : String ) {
				if( !sys.FileSystem.exists(dir) ) return;
				for( f in sys.FileSystem.readDirectory(dir) ) {
					var path = js.node.Path.join(dir, f);
					if( StringTools.endsWith(f, ext) && !sys.FileSystem.isDirectory(path) )
						add(prefix + f, js.node.Fs.readFileSync(path), sys.FileSystem.stat(path).mtime);
				}
			}
			var versions = js.Node.process.versions;
			var text = info + "\nElectron " + versions.get("electron") + ", Chrome " + versions.get("chrome") + "\n\nGPU : " + haxe.Json.stringify(gpu, "\t") + "\n";
			add("info.txt", js.node.Buffer.from(text), Date.now());
			add("windows.txt", js.node.Buffer.from(getWindowsInfo()), Date.now());
			addDir(sessionLogs, "", ".log");
			for( dir in thumbLogs )
				addDir(dir, js.node.Path.basename(dir) + "/", ".log");
			addDir(js.node.Path.join(App.getPath("crashDumps"), "reports"), "dumps/", ".dmp");
			var out = new haxe.io.BytesOutput();
			new haxe.zip.Writer(out).write(entries);
			var dir = js.node.Path.join(App.getPath("userData"), "reports");
			if( !sys.FileSystem.exists(dir) ) sys.FileSystem.createDirectory(dir);
			var file = js.node.Path.join(dir, "crash_report_" + DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S") + ".zip");
			js.node.Fs.writeFileSync(file, js.node.Buffer.hxFromBytes(out.getBytes()));
			Shell.showItemInFolder(file);
			return file;
		});
	}

	static function getWin( wc : WebContents, id : Null<Int> ) {
		var win = id == null ? BrowserWindow.fromWebContents(wc) : BrowserWindow.fromId(id);
		if( win == null || win.isDestroyed() ) throw "Window not found " + id;
		return win;
	}

	// ---------------- windows

	static function dispatchWinEvent( winId : Int, event : String ) {
		var subs = subscriptions.get(winId);
		if( subs == null ) return;
		for( wcId => events in subs )
			if( events.indexOf(event) >= 0 )
				send(WebContents.fromId(wcId), "hide-win-event", winId, event);
	}

	static function createWindow( file : String, opts : CreateWindowOptions ) {
		var show = opts.show != false;
		var win = new BrowserWindow({
			width : opts.width == null ? 800 : opts.width,
			height : opts.height == null ? 600 : opts.height,
			show : show && !background,
			title : opts.title == null ? appTitle : opts.title,
			// ICO is only supported on Windows
			icon : js.node.Path.join(js.Node.__dirname, "res", (isCDB ? "cdb." : "hide.") + (js.Node.process.platform == "win32" ? "ico" : "png")),
			backgroundColor : "#222222",
			webPreferences : {
				nodeIntegration : true,
				nodeIntegrationInWorker : true,
				contextIsolation : false,
				sandbox : false,
				webviewTag : true,
				webSecurity : false,
				backgroundThrottling : false,
				spellcheck : true,
				preload : testMode ? js.node.Path.join(js.Node.__dirname, "test-preload.js") : null,
			},
		});
		var id = win.id;
		var wcId = win.webContents.id;
		var state : WindowState = { interceptClose : false, forceClose : false, opener : opts.opener, menu : null };
		windowStates.set(id, state);
		win.setMenu(null);
		// title is driven by hide, not by the document
		win.on("page-title-updated", (e : Dynamic) -> e.preventDefault());

		win.on("close", function(e : Dynamic) {
			if( state.forceClose || !state.interceptClose || win.webContents.isDestroyed() || win.webContents.isCrashed() ) {
				dispatchWinEvent(id, "close");
				return;
			}
			e.preventDefault();
			send(win.webContents, "hide-win-event", id, "close");
		});
		win.on("closed", function() {
			var subs = subscriptions.get(id);
			if( subs != null )
				for( wcId in subs.keys() )
					send(WebContents.fromId(wcId), "hide-win-event", id, "closed");
			subscriptions.remove(id);
			windowStates.remove(id);
		});
		for( ev in ["maximize", "minimize", "move", "resize", "focus", "blur", "show", "hide"] )
			win.on(ev, () -> dispatchWinEvent(id, ev));
		// nwjs "restore" is sent both on unmaximize and when restoring from minimize
		win.on("unmaximize", () -> dispatchWinEvent(id, "restore"));
		win.on("restore", () -> dispatchWinEvent(id, "restore"));
		win.on("enter-full-screen", () -> dispatchWinEvent(id, "enter-fullscreen"));
		win.on("leave-full-screen", () -> dispatchWinEvent(id, "leave-fullscreen"));
		win.webContents.on("render-process-gone", () -> dispatchWinEvent(id, "crashed"));

		win.webContents.on("destroyed", () -> cleanupWebContents(wcId));
		// page reload : forget what the previous page had registered
		win.webContents.on("did-start-navigation", function(e : Dynamic) {
			if( !e.isMainFrame || e.isSameDocument ) return;
			cleanupWebContents(wcId);
			state.interceptClose = false;
		});
		if( background && show )
			win.showInactive();

		var parts = file.split("?");
		// thumbnail generator : its console, load errors and losses in logs/logs_thumb_<date>_<time>
		if( parts[1] != null && parts[1].indexOf("thumbnail=true") >= 0 ) {
			var dir = js.node.Path.join(js.node.Path.dirname(sessionLogs), "logs_thumb_" + DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S"));
			sys.FileSystem.createDirectory(dir);
			// two generators created in the same second share it
			if( thumbLogs.indexOf(dir) < 0 ) thumbLogs.push(dir);
			var log = js.node.Path.join(dir, "thumb.log");
			function write( text : String ) {
				js.node.Fs.appendFileSync(log, DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S") + " " + text + "\n");
			}
			win.webContents.on("console-message", (e : Dynamic) -> write(e.level + " " + e.message + " (" + e.sourceId + ":" + e.lineNumber + ")"));
			win.webContents.on("did-fail-load", (_, code : Int, desc : String, url : String) -> write("load failed " + code + " " + desc + " " + url));
			win.webContents.on("preload-error", (_, path : String, err : Dynamic) -> write("preload error " + path + " " + err));
			win.webContents.on("render-process-gone", (_, details : Dynamic) -> write("renderer " + details.reason + ", exit code " + details.exitCode));
			win.on("unresponsive", () -> write("unresponsive"));
			win.on("responsive", () -> write("responsive"));
			win.on("closed", () -> write("closed"));
		} else {
			// Chromium logs the console at the INFO level, below log-level : the warnings and errors are kept here
			var log = js.node.Path.join(sessionLogs, "console.log");
			win.webContents.on("console-message", function( e : Dynamic ) {
				if( e.level == "warning" || e.level == "error" )
					js.node.Fs.appendFileSync(log, DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S") + " " + e.level + " " + e.message + " (" + e.sourceId + ":" + e.lineNumber + ")\n");
			});
		}
		var fileUrl : String = js.Lib.require("url").pathToFileURL(js.node.Path.join(js.Node.__dirname, parts[0])).href;
		win.loadURL(parts[1] == null ? fileUrl : fileUrl + "?" + parts[1]);
		return win;
	}

	static function cleanupWebContents( wcId : Int ) {
		for( subs in subscriptions )
			subs.remove(wcId);
		var keys = shortcuts.get(wcId);
		if( keys != null ) {
			for( k in keys )
				GlobalShortcut.unregister(k);
			shortcuts.remove(wcId);
		}
	}

	static function menuFromTemplate( wc : WebContents, items : Array<Dynamic> ) : Array<Dynamic> {
		return [for( it in items ) {
			if( it.type == "separator" ) { type : "separator" } else {
				var m : Dynamic = {
					id : it.id,
					label : it.label,
					type : it.submenu != null ? "submenu" : (it.type == "checkbox" ? "checkbox" : "normal"),
					enabled : it.enabled != false,
				};
				if( it.type == "checkbox" ) m.checked = it.checked == true;
				if( it.accelerator != null ) m.accelerator = it.accelerator;
				if( it.submenu != null )
					m.submenu = menuFromTemplate(wc, it.submenu);
				else {
					var itemId : String = it.id;
					m.click = () -> send(wc, "hide-menu-click", itemId);
				}
				m;
			}
		}];
	}

	// Electron rejects null options
	static function dialogOptions( o : Dynamic, opts : Dynamic ) : Dynamic {
		if( o.defaultPath != null ) opts.defaultPath = o.defaultPath;
		if( o.exts != null ) opts.filters = [{ name : "Files", extensions : o.exts }, { name : "All Files", extensions : ["*"] }];
		return opts;
	}

	// ---------------- commands

	static function runCommand( wc : WebContents, cmd : String, args : Array<Dynamic> ) : Dynamic {
		var h = handlers.get(cmd);
		if( h == null ) throw "Unknown command " + cmd;
		return Reflect.callMethod(null, h, [(wc : Dynamic)].concat(args));
	}

	static function initHandlers() {
		var h = handlers;

		h.set("hello", function(wc : WebContents) {
			// called when a page (re)loads : reset everything it had registered
			cleanupWebContents(wc.id);
			var win = BrowserWindow.fromWebContents(wc);
			if( win != null ) windowStates.get(win.id).interceptClose = false;
			return {
				argv : filterArgv(js.Node.process.argv),
				dataPath : App.getPath("userData"),
				name : appName,
				windowId : win == null ? null : win.id,
				version : js.Node.process.versions.get("electron"),
			};
		});

		// app
		h.set("app.quit", (wc) -> App.quit());
		h.set("app.isDebuggerAttached", (wc) -> isDebuggerAttached(wc));
		h.set("app.clearCache", (wc : WebContents) -> wc.session.clearCache());
		h.set("app.createCrashReport", (wc, info : String) -> createCrashReport(info));
		h.set("shortcut.register", function(wc : WebContents, accel : String) {
			var ok = GlobalShortcut.register(accel, () -> send(wc, "hide-shortcut", accel));
			if( ok ) {
				var keys = shortcuts.get(wc.id);
				if( keys == null ) shortcuts.set(wc.id, keys = []);
				keys.push(accel);
			}
			return ok;
		});
		h.set("shortcut.unregister", function(wc : WebContents, accel : String) {
			GlobalShortcut.unregister(accel);
			var keys = shortcuts.get(wc.id);
			if( keys != null ) keys.remove(accel);
		});

		// screens
		h.set("screen.all", (wc) -> [for( d in Screen.getAllDisplays() ) {
			id : d.id,
			bounds : d.bounds,
			work_area : d.workArea,
			scaleFactor : d.scaleFactor,
			isBuiltIn : d.internal,
			rotation : d.rotation,
			touchSupport : d.touchSupport,
		}]);

		// clipboard (async in Electron, exposed as sync to the renderer)
		h.set("clipboard.get", function(wc, type : String) : js.lib.Promise<String> {
			if( type == null || type == "text" )
				return Clipboard.readText();
			var mime = MIMES.exists(type) ? MIMES.get(type) : type;
			return Clipboard.read().then(function(items) {
				for( it in items )
					if( it.types.indexOf(mime) >= 0 )
						return it.getType(mime).then((b : Dynamic) -> (b.text() : js.lib.Promise<String>));
				return js.lib.Promise.resolve("");
			});
		});
		h.set("clipboard.set", function(wc, datas : Array<{ data : String, type : String }>) {
			var item : haxe.DynamicAccess<String> = {};
			for( d in datas ) {
				var type = d.type == null ? "text" : d.type;
				item.set(MIMES.exists(type) ? MIMES.get(type) : type, d.data);
			}
			return Clipboard.write([new ClipboardItem(cast item)]);
		});
		h.set("clipboard.clear", (wc) -> Clipboard.clear());

		// windows
		h.set("win.open", function(wc : WebContents, file : String, opts : CreateWindowOptions) {
			if( opts == null ) opts = {};
			opts.opener = wc.id;
			return createWindow(file, opts).id;
		});
		h.set("win.list", (wc) -> [for( w in BrowserWindow.getAllWindows() ) { id : w.id, title : w.getTitle() }]);
		h.set("win.subscribe", function(wc : WebContents, id : Null<Int>, events : Array<String>) {
			var win = getWin(wc, id);
			var subs = subscriptions.get(win.id);
			if( subs == null ) subscriptions.set(win.id, subs = new Map());
			var evs = subs.get(wc.id);
			if( evs == null ) subs.set(wc.id, evs = []);
			for( e in events ) {
				if( evs.indexOf(e) < 0 ) evs.push(e);
				if( e == "close" && win.webContents == wc ) windowStates.get(win.id).interceptClose = true;
			}
		});
		h.set("win.getBounds", (wc, id) -> getWin(wc, id).getBounds());
		h.set("win.getTitle", (wc, id) -> getWin(wc, id).getTitle());
		h.set("win.setTitle", (wc, id, title : String) -> getWin(wc, id).setTitle(title));
		h.set("win.isMaximized", (wc, id) -> getWin(wc, id).isMaximized());
		h.set("win.moveTo", (wc, id, x : Float, y : Float) -> getWin(wc, id).setPosition(Math.round(x), Math.round(y)));
		h.set("win.resizeTo", (wc, id, w : Float, h : Float) -> getWin(wc, id).setSize(Math.round(w), Math.round(h)));
		h.set("win.resizeBy", function(wc, id, dw : Float, dh : Float) {
			var win = getWin(wc, id);
			var size = win.getSize();
			win.setSize(Math.round(size[0] + dw), Math.round(size[1] + dh));
		});
		h.set("win.maximize", (wc, id) -> if( !background ) getWin(wc, id).maximize());
		h.set("win.minimize", (wc, id) -> getWin(wc, id).minimize());
		h.set("win.restore", function(wc, id) {
			var win = getWin(wc, id);
			if( win.isMaximized() ) win.unmaximize() else win.restore();
		});
		h.set("win.setFullScreen", (wc, id, b : Bool) -> if( !background ) getWin(wc, id).setFullScreen(b));
		h.set("win.show", function(wc, id, b : Bool) {
			var win = getWin(wc, id);
			if( b == false ) win.hide() else if( background ) win.showInactive() else win.show();
		});
		h.set("win.focus", (wc, id) -> if( !background ) getWin(wc, id).focus());
		h.set("win.blur", (wc, id) -> getWin(wc, id).blur());
		h.set("win.close", function(wc : WebContents, id : Null<Int>, force : Bool) {
			var win = id == null ? BrowserWindow.fromWebContents(wc) : BrowserWindow.fromId(id);
			if( win == null || win.isDestroyed() ) return;
			if( force ) windowStates.get(win.id).forceClose = true;
			win.close();
		});
		h.set("win.toggleDevTools", (wc, id) -> getWin(wc, id).webContents.toggleDevTools());
		h.set("win.setMenu", function(wc : WebContents, items : Array<Dynamic>) {
			var win = getWin(wc, null);
			var template = items == null ? null : menuFromTemplate(wc, items);
			// without an Edit menu, copy/paste shortcuts are not handled on OSX
			if( template != null && Sys.systemName() == "Mac" )
				template = ([{ role : "appMenu" }, { role : "editMenu" }] : Array<Dynamic>).concat(template);
			var menu = template == null ? null : Menu.buildFromTemplate(template);
			if( Sys.systemName() == "Mac" ) {
				if( win == mainWindow ) Menu.setApplicationMenu(menu);
			} else
				win.setMenu(menu);
			windowStates.get(win.id).menu = menu;
		});
		h.set("win.updateMenuItem", function(wc, itemId : String, props : haxe.DynamicAccess<Dynamic>) {
			var menu = windowStates.get(getWin(wc, null).id).menu;
			var item = menu == null ? null : menu.getMenuItemById(itemId);
			if( item == null ) return;
			for( k => v in props ) Reflect.setField(item, k, v);
		});
		h.set("win.callParent", function(wc, name : String, param : Dynamic) {
			var opener = windowStates.get(getWin(wc, null).id).opener;
			if( opener != null ) send(WebContents.fromId(opener), "hide-parent-call", name, param);
		});
		h.set("win.connectOpener", function(wc : WebContents) {
			var win = getWin(wc, null);
			var opener = windowStates.get(win.id).opener;
			var openerWc = opener == null ? null : WebContents.fromId(opener);
			if( openerWc == null || openerWc.isDestroyed() ) throw "Window has no opener";
			var channel = new MessageChannelMain();
			openerWc.postMessage("hide-port", win.id, [channel.port1]);
			wc.postMessage("hide-port", null, [channel.port2]);
		});

		// values shared between windows (must be serializable)
		h.set("shared.set", function(wc, value : Dynamic) {
			var id = sharedRefId++;
			sharedRefs.set(id, value);
			return id;
		});
		h.set("shared.get", (wc, id : Int) -> sharedRefs.get(id));

		// dialogs
		h.set("dialog.open", function(wc, o : Dynamic) {
			var props = [o.directory ? "openDirectory" : "openFile", "createDirectory"];
			if( o.multiple ) props.push("multiSelections");
			return Dialog.showOpenDialog(getWin(wc, null), dialogOptions(o, { properties : props }))
				.then((r) -> r.canceled || r.filePaths.length == 0 ? null : r.filePaths);
		});
		h.set("dialog.save", function(wc, o : Dynamic) {
			return Dialog.showSaveDialog(getWin(wc, null), dialogOptions(o, {}))
				.then((r) -> r.canceled || r.filePath == null || r.filePath == "" ? null : [r.filePath]);
		});
		// window.prompt() is not supported by Electron
		h.set("dialog.prompt", (wc, text : String, value : String) -> new js.lib.Promise<String>(function(resolve, _) {
			if( testMode ) {
				js.Browser.console.log("[prompt] " + text);
				resolve(value == null ? "" : value);
				return;
			}
			var parent = BrowserWindow.fromWebContents(wc);
			var w = new BrowserWindow({
				parent : parent,
				modal : true,
				width : 450,
				height : 150,
				useContentSize : true,
				resizable : false,
				minimizable : false,
				maximizable : false,
				show : false,
				title : parent == null ? appTitle : parent.getTitle(),
				backgroundColor : "#222222",
				webPreferences : { nodeIntegration : true, contextIsolation : false, sandbox : false },
			});
			w.setMenu(null);
			var result : String = null;
			var promptWc = w.webContents;
			function onAnswer( e : Dynamic, v : String ) {
				if( e.sender != promptWc ) return;
				result = v;
				w.close();
			}
			IpcMain.on("hide-prompt-answer", onAnswer);
			w.on("closed", function() {
				IpcMain.off("hide-prompt-answer", onAnswer);
				resolve(result);
			});
			w.once("ready-to-show", () -> w.show());
			w.loadFile(js.node.Path.join(js.Node.__dirname, "prompt.html"), { query : { text : Std.string(text), value : value == null ? "" : Std.string(value) } });
		}));

		// devtools embedded into a <webview>
		h.set("devtools.attach", function(wc, targetId : Int, devtoolsId : Int) {
			var target = WebContents.fromId(targetId);
			target.setDevToolsWebContents(WebContents.fromId(devtoolsId));
			target.openDevTools();
		});
		h.set("devtools.open", (wc, wcId : Int) -> WebContents.fromId(wcId).openDevTools({ mode : "detach" }));
	}

}
