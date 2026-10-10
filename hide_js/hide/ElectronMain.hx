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
	// HIDE_TEST=1 (automated testing) : replace alert/confirm popups by console logs and
	// never activate / focus / maximize windows so they stay in the background
	static var testMode : Bool;

	static var mainWindow : BrowserWindow;
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
		isCDB = argv.indexOf("--cdb") >= 0 || env.get("HIDE_START_CDB") == "1";
		testMode = env.get("HIDE_TEST") == "1";
		appName = isCDB ? "CDB" : "hide";
		appTitle = isCDB ? "CDB" : "HIDE";

		App.setName(appName);
		App.setPath("userData", js.node.Path.join(App.getPath("appData"), appName));
		App.commandLine.appendSwitch("js-flags", "--expose-gc --no-efficiency-mode");
		// test mode : the windows stay behind the user's ones, they must still render (scroll, animation frames, screenshots)
		App.commandLine.appendSwitch("disable-features", "AllowSoftwareGLFallbackDueToCrashes" + (testMode ? ",CalculateNativeWinOcclusion" : ""));
		if( testMode ) {
			App.commandLine.appendSwitch("disable-renderer-backgrounding");
			App.commandLine.appendSwitch("disable-backgrounding-occluded-windows");
		}
		// DirectX 12 (jsdx) : Chromium must use the same GPU as the dx12 addon, shared textures can not cross adapters
		App.commandLine.appendSwitch("force_high_performance_gpu");
		App.commandLine.appendSwitch("ignore-gpu-blocklist");

		if( !App.requestSingleInstanceLock() ) {
			App.quit();
			return;
		}

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
			if( !testMode ) mainWindow.focus();
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
			for( s in windowStates ) s.forceClose = true;
		});
		App.on("window-all-closed", () -> App.quit());
		App.on("will-quit", () -> GlobalShortcut.unregisterAll());

		App.whenReady().then(function(_) {
			Menu.setApplicationMenu(null);
			try Session.defaultSession.setSpellCheckerLanguages(["en-US", "fr-FR"]) catch( e : Dynamic ) {}
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
			show : show && !testMode,
			title : opts.title == null ? appTitle : opts.title,
			icon : js.node.Path.join(js.Node.__dirname, "res", isCDB ? "cdb.png" : "hide.png"),
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

		win.webContents.on("destroyed", () -> cleanupWebContents(wcId));
		// page reload : forget what the previous page had registered
		win.webContents.on("did-start-navigation", function(e : Dynamic) {
			if( !e.isMainFrame || e.isSameDocument ) return;
			cleanupWebContents(wcId);
			state.interceptClose = false;
		});
		if( testMode && show )
			win.showInactive();

		var parts = file.split("?");
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
		h.set("app.clearCache", (wc : WebContents) -> wc.session.clearCache());
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
		h.set("win.maximize", (wc, id) -> if( !testMode ) getWin(wc, id).maximize());
		h.set("win.minimize", (wc, id) -> getWin(wc, id).minimize());
		h.set("win.restore", function(wc, id) {
			var win = getWin(wc, id);
			if( win.isMaximized() ) win.unmaximize() else win.restore();
		});
		h.set("win.setFullScreen", (wc, id, b : Bool) -> if( !testMode ) getWin(wc, id).setFullScreen(b));
		h.set("win.show", function(wc, id, b : Bool) {
			var win = getWin(wc, id);
			if( b == false ) win.hide() else if( testMode ) win.showInactive() else win.show();
		});
		h.set("win.focus", (wc, id) -> if( !testMode ) getWin(wc, id).focus());
		h.set("win.blur", (wc, id) -> getWin(wc, id).blur());
		h.set("win.close", function(wc : WebContents, id : Null<Int>, force : Bool) {
			var win = id == null ? BrowserWindow.fromWebContents(wc) : BrowserWindow.fromId(id);
			if( win == null || win.isDestroyed() ) return;
			if( force ) windowStates.get(win.id).forceClose = true;
			win.close();
		});
		h.set("win.openDevTools", (wc, id) -> getWin(wc, id).webContents.openDevTools());
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
