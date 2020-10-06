package hide;
import hxd.inspect.Group;

@:expose
class Ide {

	public var currentConfig(get,never) : Config;
	public var projectDir(get,never) : String;
	public var resourceDir(get,never) : String;
	public var initializing(default,null) : Bool;
	public var appPath(get, null): String;

	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	public var isWindows(get, never) : Bool;
	public var isFocused(get, never) : Bool;

	public var database : cdb.Database;
	public var shaderLoader : hide.tools.ShaderLoader;
	public var fileWatcher : hide.tools.FileWatcher;
	public var typesCache : hide.tools.TypesCache;
	public var isCDB = false;
	public var isDebugger = false;

	public var gamePad(default,null) : hxd.Pad;

	var databaseFile : String;
	var databaseDiff : String;
	var pakFile : hxd.fmt.pak.FileSystem;
	var originDataBase : cdb.Database;
	var dbWatcher : hide.tools.FileWatcher.FileWatchEvent;

	var config : {
		global : Config,
		project : Config,
		user : Config,
		current : Config,
	};
	var ideConfig(get, never) : hide.Config.HideGlobalConfig;
	var projectConfig(get, never) : hide.Config.HideProjectConfig;

	var window : nw.Window;
	var saveMenu : nw.Menu;
	var layout : golden.Layout;

	var currentLayout : { name : String, state : Config.LayoutState };
	var defaultLayout : { name : String, state : Config.LayoutState };
	var currentFullScreen(default,set) : hide.ui.View<Dynamic>;
	var maximized : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<hide.ui.View<Dynamic>> = [];

	var renderers : Array<h3d.mat.MaterialSetup>;
	var subView : { component : String, state : Dynamic, events : {} };
	var scripts : Map<String,Array<Void->Void>> = new Map();
	var hasReloaded = false;

	static var firstInit = true;

	function new() {
		initPad();
		isCDB = Sys.getEnv("HIDE_START_CDB") == "1" || nw.App.manifest.name == "CDB";
		isDebugger = Sys.getEnv("HIDE_DEBUG") == "1";
		function wait() {
			if( monaco.ScriptEditor == null ) {
				haxe.Timer.delay(wait, 10);
				return;
			}
			startup();
		}
		wait();
	}

	function initPad() {
		gamePad = hxd.Pad.createDummy();
		hxd.Pad.wait((p) -> gamePad = p);
	}

	function startup() {
		inst = this;
		window = nw.Window.get();
		var cwd = Sys.getCwd();
		config = Config.loadForProject(cwd, cwd+"/res");
		var current = ideConfig.currentProject;
		if( StringTools.endsWith(cwd,"package.nw") && sys.FileSystem.exists(cwd.substr(0,-10)+"res") )
			cwd = cwd.substr(0,-11);
		if( current == "" ) cwd;

		var args = js.Browser.document.URL.split("?")[1];
		if( args != null ) {
			var parts = args.split("&");
			var vars = new Map();
			for( p in parts ) {
				var p = p.split("=");
				vars.set(p[0],StringTools.urlDecode(p[1]));
			}
			var sub = vars.get("subView");
			if( sub != null ) {
				var obj = untyped global.sharedRefs.get(Std.parseInt(vars.get("sid")));
				subView = { component : sub, state : obj.state, events : obj.events };
			}
		}

		if( subView == null ) {
			var wp = ideConfig.windowPos;
			if( wp != null ) {
				if( wp.w > 400 && wp.h > 300 )
					window.resizeBy(wp.w - Std.int(window.window.outerWidth), wp.h - Std.int(window.window.outerHeight));
				if( wp.x >= 0 && wp.y >= 0 )
					window.moveTo(wp.x, wp.y);
				if( wp.max ) {
					window.maximize();
					maximized = true;
				}
			}
		}
		window.show(true);

		if( config.global.get("hide") == null )
			error("Failed to load defaultProps.json");

		fileWatcher = new hide.tools.FileWatcher();

		if( !sys.FileSystem.exists(current) || !sys.FileSystem.isDirectory(current) ) {
			if( current != "" ) js.Browser.alert(current+" no longer exists");
			current = cwd;
		}

		setProject(current);
		window.window.document.addEventListener("mousedown", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		window.window.document.addEventListener("mousemove", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		window.on('maximize', function() { maximized = true; onWindowChange(); });
		window.on('restore', function() { maximized = false; onWindowChange(); });
		window.on('move', function() haxe.Timer.delay(onWindowChange,100));
		window.on('resize', function() haxe.Timer.delay(onWindowChange,100));
		window.on('close', function() {
			if( hasReloaded ) return;
			if( !isDebugger )
				for( v in views )
					if( !v.onBeforeClose() )
						return;
			window.close(true);
		});
		window.on("blur", function() { if( h3d.Engine.getCurrent() != null && !hasReloaded ) hxd.Key.initialize(); });

		// handle commandline parameters
		nw.App.on("open", function(cmd) {
			if( hasReloaded ) return;
			~/"([^"]+)"/g.map(cmd, function(r) {
				var file = r.matched(1);
				if( sys.FileSystem.exists(file) ) openFile(file);
				return "";
			});
		});

		// handle cancel on type=file
		var body = window.window.document.body;
		body.onfocus = function(_) haxe.Timer.delay(function() new Element(body).find("input[type=file]").change().remove(), 200);
		function dragFunc(drop : Bool, e:js.html.DragEvent) {
			syncMousePosition(e);
			var view = getViewAt(mouseX, mouseY);
			var items : Array<String> = [for(f in e.dataTransfer.files) Reflect.field(f, "path")];
			if(view != null && view.onDragDrop(items, drop)) {
				e.preventDefault();
				e.stopPropagation();
				return true;
			}
			return false;
		}
		body.ondragover = function(e:js.html.DragEvent) {
			dragFunc(false, e);
			return false;
		};
		body.ondrop = function(e:js.html.DragEvent) {
			if(!dragFunc(true, e)) {
				for( f in e.dataTransfer.files )
					openFile(Reflect.field(f,"path"));
				e.preventDefault();
			}
			return false;
		}

		if( subView != null ) body.className +=" hide-subview";

		// Listen to FileTree dnd
		function treeDragFun(data,drop) {
			var nodeIds : Array<String> = cast data.data.nodes;
			if(data.data.jstree == null) return false;
			for( ft in getViews(hide.view.FileTree) ) {
				var paths = [];
				@:privateAccess {
					if(ft.tree.element[0] != data.data.origin.element[0]) continue;
					for(id in nodeIds) {
						var item = ft.tree.map.get(id);
						if(item != null)
							paths.push(item.value);
					}
				}
				if(paths.length == 0)
					continue;
				var view = getViewAt(mouseX, mouseY);
				if(view != null)
					return view.onDragDrop(paths, drop);
			}
			return false;
		}
		new Element(window.window.document).on("dnd_move.vakata.jstree", function(e, data:Dynamic) {
			(data.helper:hide.Element).css(treeDragFun(data,false) ? { filter : "brightness(120%)", opacity : 1 } : { filter : "", opacity : 0.5 });
		});
		new Element(window.window.document).on("dnd_stop.vakata.jstree", function(e, data) {
			treeDragFun(data,true);
		});

		// dispatch global keys based on mouse position
		new Element(body).keydown(function(e) {
			var view = getViewAt(mouseX, mouseY);
			if(view != null) view.processKeyEvent(e);
		});
	}

	public function getViews<K,T:hide.ui.View<K>>( cl : Class<T> ) {
		return [for( v in views ) { var t = Std.downcast(v,cl); if( t != null ) t; }];
	}

	function getViewAt(x : Float, y : Float) {
		var pickedEl = js.Browser.document.elementFromPoint(x, y);
		for( v in views ) {
			var viewEl = v.element[0];
			var el = pickedEl;
			while(el != null) {
				if(el == viewEl) return v;
				el = el.parentElement;
			}
		}
		return null;
	}

	function syncMousePosition(e:js.html.MouseEvent) {
		mouseX = e.clientX;
		mouseY = e.clientY;
		for( c in new Element("canvas") ) {
			var s : hide.comp.Scene = (c:Dynamic).__scene;
			if( s != null ) @:privateAccess {
				s.window.curMouseX = mouseX;
				s.window.curMouseY = mouseY;
			}
		}
	}

	function get_isWindows() {
		return true;
	}

	function get_isFocused() {
		return js.Browser.document.hasFocus();
	}

	function onWindowChange() {
		if( hasReloaded )
			return;
		if( ideConfig.windowPos == null ) ideConfig.windowPos = { x : 0, y : 0, w : 0, h : 0, max : false };
		ideConfig.windowPos.max = maximized;
		if( !maximized ) {
			ideConfig.windowPos.x = window.x;
			ideConfig.windowPos.y = window.y;
			ideConfig.windowPos.w = Std.int(window.window.outerWidth);
			ideConfig.windowPos.h = Std.int(window.window.outerHeight);
		}
		if( subView == null )
			config.global.save();
	}

	function initLayout( ?state : { name : String, state : Config.LayoutState } ) {
		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		defaultLayout = null;
		var layoutName = isCDB ? "CDB" : "Default";
		var emptyLayout : Config.LayoutState = { content : [], fullScreen : null };
		for( p in projectConfig.layouts )
			if( p.name == layoutName ) {
				if( p.state.content == null ) continue; // old version
				defaultLayout = p;
				break;
			}
		if( defaultLayout == null ) {
			defaultLayout = { name : layoutName, state : emptyLayout };
			projectConfig.layouts.push(defaultLayout);
			config.current.sync();
			config.user.save();
		}
		if( state == null )
			state = defaultLayout;

		if( subView != null )
			state = { name : "SubView", state : emptyLayout };

		this.currentLayout = state;

		var config : golden.Config = {
			content: state.state.content,
		};
		var comps = new Map();
		for( vcl in hide.ui.View.viewClasses )
			comps.set(vcl.name, true);
		function checkRec(i:golden.Config.ItemConfig) {
			if( i.componentName != null && !comps.exists(i.componentName) ) {
				i.componentState.deletedComponent = i.componentName;
				i.componentName = "hide.view.Unknown";
			}
			if( i.content != null ) for( i in i.content ) checkRec(i);
		}
		for( i in config.content ) checkRec(i);

		layout = new golden.Layout(config);

		var initViews = [];
		function initView(view:hide.ui.View<Dynamic>) {
			if( isDebugger ) view.rebuild() else try view.rebuild() catch( e : Dynamic ) error(view+":"+e);
		}
		for( vcl in hide.ui.View.viewClasses )
			layout.registerComponent(vcl.name,function(cont,state) {
				var view = Type.createInstance(vcl.cl,[state]);
				view.setContainer(cont);
				if( initializing )
					initViews.push(view);
				else
					initView(view);
			});

		layout.init();
		layout.on('stateChanged', onLayoutChanged);

		var waitCount = 0;
		function waitInit() {
			waitCount++;
			if( !layout.isInitialised ) {
				if( waitCount > 20 ) {
					// timeout : error recovery if invalid component
					state.state = emptyLayout;
					initLayout();
					return;
				}
				haxe.Timer.delay(waitInit, 50);
				return;
			}
			if( state.state.fullScreen != null ) {
				var fs = state.state.fullScreen;
				var found = [for( v in views ) if( v.viewClass == fs.name ) v];
				if( found.length == 1 )
					found[0].fullScreen = true;
				else {
					for( f in found )
						if( haxe.Json.stringify(f.state) == haxe.Json.stringify(fs.state) ) {
							f.fullScreen = true;
							break;
						}
				}
			}
			initializing = false;
			for( v in initViews )
				initView(v);
			initViews = null;
			if( subView == null && views.length == 0 ) {
				if( isCDB )
					open("hide.view.CdbTable",{}, function(v) v.fullScreen = true);
				else
					open("hide.view.FileTree",{path:""});
			}
			if( firstInit ) {
				firstInit = false;
				for( file in nw.App.argv ) {
					if( !sys.FileSystem.exists(file) ) continue;
					openFile(file);
				}
				if( subView != null )
					open(subView.component, subView.state);
			}
		};
		waitInit();

		hxd.System.setLoop(mainLoop);
	}

	function mainLoop() {
		hxd.Timer.update();
		@:privateAccess hxd.Pad.syncPads();
		for( f in updates )
			f();
	}

	public function setFullscreen(b : Bool) {
		if (b) {
			window.maximize();
			saveMenu = window.menu;
			window.menu = null;
			window.enterFullscreen();
		} else {
			window.menu = saveMenu;
			window.leaveFullscreen();
		}
	}

	function set_currentFullScreen(v) {
		var old = currentFullScreen;
		currentFullScreen = v;
		if( old != null ) old.fullScreen = false;
		onLayoutChanged();
		return v;
	}

	function onLayoutChanged() {
		if( initializing || !ideConfig.autoSaveLayout || isCDB )
			return;
		defaultLayout.state = saveLayout();
		if( subView == null ) this.config.user.save();
	}

	function saveLayout() : Config.LayoutState {
		return {
			content : layout.toConfig().content,
			fullScreen : currentFullScreen == null ? null : { name : currentFullScreen.viewClass, state : currentFullScreen.state }
		};
	}

	function get_ideConfig() return cast config.global.source.hide;
	function get_projectConfig() return cast config.user.source.hide;
	function get_currentConfig() return config.user;

	function get_appPath() {
		if( appPath != null )
			return appPath;
		var path = js.Node.process.argv[0].split("\\").join("/").split("/");
		path.pop();
		var hidePath = path.join("/");
		if( !sys.FileSystem.exists(hidePath + "/package.json") ) {
			var prevPath = new haxe.io.Path(hidePath).dir;
			if( sys.FileSystem.exists(prevPath + "/hide.js") )
				return appPath = prevPath;
			// nwjs launch
			var path = Sys.getCwd().split("\\").join("/");
			if( sys.FileSystem.exists(path+"/hide.js") )
				return appPath = path;
			message("Hide application path was not found");
			Sys.exit(0);
		}
		return appPath = hidePath;
	}

	public function setClipboard( text : String ) {
		nw.Clipboard.get().set(text, Text);
	}

	public function getClipboard() {
		return nw.Clipboard.get().get(Text);
	}

	public function registerUpdate( updateFun ) {
		updates.push(updateFun);
	}

	public function unregisterUpdate( updateFun ) {
		for( u in updates )
			if( Reflect.compareMethods(u,updateFun) ) {
				updates.remove(u);
				return true;
			}
		return false;
	}

	public function cleanObject( v : Dynamic ) {
		for( f in Reflect.fields(v) )
			if( Reflect.field(v, f) == null )
				Reflect.deleteField(v, f);
	}

	public function getPath( relPath : String ) {
		if( relPath == null )
			return null;
		relPath = relPath.split("${HIDE}").join(appPath);
		if( haxe.io.Path.isAbsolute(relPath) )
			return relPath;
		return resourceDir+"/"+relPath;
	}

	var showErrors = true;
	public function error( e : Dynamic ) {
		if( showErrors && !js.Browser.window.confirm(e) )
			showErrors = false;
		js.Browser.console.error(e);
	}

	function get_projectDir() return ideConfig.currentProject.split("\\").join("/");
	function get_resourceDir() return projectDir+"/res";

	function setProject( dir : String ) {
		fileWatcher.dispose();

		if( dir != ideConfig.currentProject ) {
			ideConfig.currentProject = dir;
			ideConfig.recentProjects.remove(dir);
			ideConfig.recentProjects.unshift(dir);
			if( ideConfig.recentProjects.length > 10 ) ideConfig.recentProjects.pop();
			config.global.save();
		}
		try {
			config = Config.loadForProject(projectDir, resourceDir);
		} catch( e : Dynamic ) {
			js.Browser.alert(e);
			return;
		}
		var title = config.current.get("hide.windowTitle");
		window.title = title != null ? title : ((isCDB ? "CastleDB" : "HIDE") + " - " + dir);
		shaderLoader = new hide.tools.ShaderLoader();
		typesCache = new hide.tools.TypesCache();

		var localDir = sys.FileSystem.exists(resourceDir) ? resourceDir : projectDir;
		var fsconf = config.current.get("fs.config", "default");
		hxd.res.Loader.currentInstance = new CustomLoader(new hxd.fs.LocalFileSystem(localDir,fsconf));
		renderers = [
			new hide.Renderer.MaterialSetup("Default"),
			new hide.Renderer.PbrSetup("PBR"),
		];

		var plugins : Array<String> = config.current.get("plugins");
		for ( plugin in plugins )
			loadPlugin(plugin, function() {});

		databaseFile = config.project.get("cdb.databaseFile");
		databaseDiff = config.user.get("cdb.databaseDiff");
		var pak = config.project.get("pak.dataFile");
		pakFile = null;
		if( pak != null ) {
			pakFile = new hxd.fmt.pak.FileSystem();
			try {
				pakFile.loadPak(getPath(pak));
			} catch( e : Dynamic ) {
				error(""+e);
			}
		}
		loadDatabase();
		dbWatcher = fileWatcher.register(databaseFile,function() {
			loadDatabase(true);
			hide.comp.cdb.Editor.refreshAll(true);
		});

		if( config.project.get("debug.displayErrors")  ) {
			js.Browser.window.onerror = function(msg, url, line, col, error) {
				var e = error.stack;
				e = ~/\(?chrome-extension:\/\/[a-z0-9\-\.\/]+.js:[0-9]+:[0-9]+\)?/g.replace(e,"");
				e = ~/at ([A-Za-z0-9_\.\$]+)/g.map(e,function(r) { var path = r.matched(1); path = path.split("$hx_exports.").pop().split("$hxClasses.").pop(); return path; });
				e = e.split("\t").join("    ");
				this.error(e);
				return true;
			};
		} else
			Reflect.deleteField(js.Browser.window, "onerror");

		waitScripts(function() {
			var extraRenderers = config.current.get("renderers");
			for( name in Reflect.fields(extraRenderers) ) {
				var clName = Reflect.field(extraRenderers, name);
				var cl = try js.Lib.eval(clName) catch( e : Dynamic ) null;
				if( cl == null  ) {
					error(clName+" could not be found");
					return;
				}
				renderers.push(Type.createInstance(cl,[]));
			}

			var render = renderers[0];
			if( projectConfig.renderer == null )
				projectConfig.renderer = config.current.get("defaultRenderer");
			for( r in renderers )
				if( r.name == projectConfig.renderer ) {
					render = r;
					break;
				}
			h3d.mat.MaterialSetup.current = render;

			initMenu();
			initLayout();
		});
	}

	function waitScripts( f : Void -> Void ) {
		if( !isScriptLoading() ) {
			f();
			return;
		}
		var wait = scripts.get("");
		if( wait == null ) {
			wait = [];
			scripts.set("",wait);
		}
		wait.push(f);
	}

	function isScriptLoading() {
		for( s in scripts.keys() )
			if( s != "" && scripts.get(s).length > 0 )
				return true;
		return false;
	}

	function loadPlugin( file : String, callb : Void -> Void, ?forceType : String ) {
		file = getPath(file);
		var wait = scripts.get(file);
		if( wait != null ) {
			if( wait.length == 0 )
				callb();
			else
				wait.push(callb);
			return;
		}
		wait = [callb];
		scripts.set(file, wait);
		function onLoad() {
			scripts.set(file, []);
			for( w in wait )
				w();
			if( !isScriptLoading() ) {
				wait = scripts.get("");
				scripts.set("",[]);
				for( w in wait ) w();
			}
		}
		function onError() {
			error("Error while loading "+file);
		}
		var type = forceType == null ? haxe.io.Path.extension(file).toLowerCase() : forceType;
		switch ( type ) {
			case "js":
				var e = js.Browser.document.createScriptElement();
				e.addEventListener("load", onLoad);
				e.addEventListener("error", onError);
				e.async = false;
				e.type = "text/javascript";
				e.src = "file://"+file.split("\\").join("/");
				js.Browser.document.body.appendChild(e);
			case "css":
				var e = js.Browser.document.createLinkElement();
				e.addEventListener("load", onLoad);
				e.addEventListener("error", onError);
				e.rel = "stylesheet";
				e.type = "text/css";
				e.href = "file://" + file.split("\\").join("/");
				js.Browser.document.body.appendChild(e);
			default: error('Unknown plugin type $type for file $file');
		}
		fileWatcher.register(file,reload);
	}

	inline function loadScript( file : String, callb : Void -> Void ) {
		loadPlugin(file, callb);
	}

	public function reload() {
		hasReloaded = true;
		fileWatcher.dispose();
		js.Browser.location.reload();
	}

	public function fileExists( path : String ) {
		if( sys.FileSystem.exists(getPath(path)) ) return true;
		if( pakFile != null && pakFile.exists(path) ) return true;
		return false;
	}

	public function getFile( path : String ) {
		var fullPath = getPath(path);
		try {
			return sys.io.File.getBytes(fullPath);
		} catch( e : Dynamic ) {
			if( pakFile != null )
				return pakFile.get(path).getBytes();
			throw e;
		}
	}


	function loadDatabase( ?checkExists ) {
		var exists = fileExists(databaseFile);
		if( checkExists && !exists )
			return; // cancel load
		database = new cdb.Database();
		if( !exists ) return;
		if( isDebugger ) {
			database.load(getFile(databaseFile).toString());
		} else try {
			database.load(getFile(databaseFile).toString());
		} catch( e : Dynamic ) {
			error(e);
			return;
		}
		if( databaseDiff != null ) {
			originDataBase = new cdb.Database();
			originDataBase.load(getFile(databaseFile).toString());
			if( fileExists(databaseDiff) ) {
				var d = new cdb.DiffFile();
				d.apply(database,parseJSON(getFile(databaseDiff).toString()),config.project.get("cdb.view"));
			}
		}
	}

	public function saveDatabase() {
		hide.comp.cdb.DataFiles.save(function() {
			if( databaseDiff != null ) {
				sys.io.File.saveContent(getPath(databaseDiff), toJSON(new cdb.DiffFile().make(originDataBase,database)));
				fileWatcher.ignorePrevChange(dbWatcher);
			} else {
				if( !sys.FileSystem.exists(getPath(databaseFile)) && fileExists(databaseFile) ) {
					// was loaded from pak, cancel changes
					loadDatabase();
					hide.comp.cdb.Editor.refreshAll();
					return;
				}
				sys.io.File.saveContent(getPath(databaseFile), database.save());
				fileWatcher.ignorePrevChange(dbWatcher);
			}
		});
	}

	public function createDBSheet( ?index : Int ) {
		var value = ask("Sheet name");
		if( value == "" || value == null ) return null;
		var s = database.createSheet(value, index);
		if( s == null ) {
			error("Name already exists");
			return null;
		}
		saveDatabase();
		hide.comp.cdb.Editor.refreshAll();
		return s;
	}

	public function makeRelative( path : String ) {
		path = path.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), resourceDir.toLowerCase()+"/") )
			return path.substr(resourceDir.length+1);

		var resParts = resourceDir.split("/");
		var pathParts = path.split("/");
		for( i in 0...resParts.length ) {
			if( pathParts[i].toLowerCase() != resParts[i].toLowerCase() ) {
				if( pathParts[i].charCodeAt(pathParts[i].length-1) == ":".code )
					return path; // drive letter change
				var newPath = pathParts.splice(i, pathParts.length - i);
				for( k in 0...resParts.length - i )
					newPath.unshift("..");
				return newPath.join("/");
			}
		}
		return path;
	}

	public static var IMG_EXTS = ["jpg", "jpeg", "gif", "png", "raw", "dds"];
	public function chooseImage( onSelect ) {
		chooseFile(IMG_EXTS, onSelect);
	}

	public function chooseFiles( exts : Array<String>, onSelect : Array<String> -> Void ) {
		var e = new Element('<input type="file" style="visibility:hidden" value="" accept="${[for( e in exts ) "."+e].join(",")}" multiple="multiple"/>');
		e.change(function(_) {
			var files = [for( f in (""+e.val()).split(";") ) f];
			if( files.length == 1 && files[0] == "" ) files.pop();
			var files = [for( f in files ) makeRelative(f)];
			e.remove();
			onSelect(files);
		}).appendTo(window.window.document.body).click();
	}

	public function chooseFile( exts : Array<String>, onSelect : Null<String> -> Void ) {
		var e = new Element('<input type="file" style="visibility:hidden" value="" accept="${[for( e in exts ) "."+e].join(",")}"/>');
		e.change(function(_) {
			var file = e.val();
			e.remove();
			onSelect(file == "" ? null : makeRelative(file));
		}).appendTo(window.window.document.body).click();
	}

	public function chooseFileSave( defaultPath : String, onSelect : String -> Void ) {
		var path = getPath(defaultPath).split("/");
		var file = path.pop();
		var c = isWindows ? "\\" : "/";
		var path = path.join(c);
		var e = new Element('<input type="file" style="visibility:hidden" value="" nwworkingdir="$path" nwsaveas="$file"/>');
		e.change(function(_) {
			var file = e.val();
			e.remove();
			onSelect(file == "" ? null : makeRelative(file));
		}).appendTo(window.window.document.body).click();
	}

	public function chooseDirectory( onSelect : String -> Void ) {
		var e = new Element('<input type="file" style="visibility:hidden" value="" nwdirectory/>');
		e.change(function(ev) {
			var dir = ev.getThis().val();
			onSelect(dir == "" ? null : makeRelative(dir));
			e.remove();
		}).appendTo(window.window.document.body).click();
	}

	public function parseJSON( str : String ) : Dynamic {
		// remove comments
		str = ~/^[ \t]+\/\/[^\n]*/gm.replace(str, "");
		return haxe.Json.parse(str);
	}

	public function toJSON( v : Dynamic ) {
		var str = haxe.Json.stringify(v, "\t");
		str = ~/,\n\t+"__id__": [0-9]+/g.replace(str, "");
		str = ~/\t+"__id__": [0-9]+,\n/g.replace(str, "");
		return str;
	}

	public function loadPrefab<T:hrt.prefab.Prefab>( file : String, ?cl : Class<T> ) : T {
		if( file == null )
			return null;
		var l = hrt.prefab.Library.create(file.split(".").pop().toLowerCase());
		try {
			l.loadData(parseJSON(sys.io.File.getContent(getPath(file))));
		} catch( e : Dynamic ) {
			error("Invalid prefab ("+e+")");
			throw e;
		}
		if( cl == null )
			return cast l;
		return l.get(cl);
	}

	public function savePrefab( file : String, f : hrt.prefab.Prefab ) {
		var content = f.saveData();
		sys.io.File.saveContent(getPath(file), toJSON(content));
	}

	public function filterPrefabs( callb : hrt.prefab.Prefab -> Bool ) {
		var exts = Lambda.array({iterator : @:privateAccess hrt.prefab.Library.registeredExtensions.keys });
		exts.push("prefab");
		var todo = [];
		browseFiles(function(path) {
			var ext = path.split(".").pop();
			if( exts.indexOf(ext) < 0 ) return;
			var prefab = loadPrefab(path);
			var changed = false;
			function filterRec(p) {
				if( callb(p) ) changed = true;
				for( ps in p.children )
					filterRec(ps);
			}
			filterRec(prefab);
			if( !changed ) return;
			todo.push(function() sys.io.File.saveContent(getPath(path), toJSON(prefab.saveData())));
		});
		for( t in todo )
			t();
	}

	function browseFiles( callb : String -> Void ) {
		function browseRec(path) {
			if( path == ".tmp" ) return;
			for( p in sys.FileSystem.readDirectory(resourceDir + "/" + path) ) {
				var p = path == "" ? p : path + "/" + p;
				if( sys.FileSystem.isDirectory(resourceDir+"/"+p) ) {
					browseRec(p);
					continue;
				}
				callb(p);
			}
		}
		browseRec("");
	}

	function initMenu() {

		if( subView != null ) return;

		var menuHTML = "<content>"+new Element("#mainmenu").html() + config.project.get("menu.extra")+"</content>";
		var menu = new Element(menuHTML);

		// project
		if( ideConfig.recentProjects.length > 0 )
			menu.find(".project .recents").html("");
		for( v in ideConfig.recentProjects.copy() ) {
			if( !sys.FileSystem.exists(v) ) {
				ideConfig.recentProjects.remove(v);
				config.global.save();
				continue;
			}
			new Element("<menu>").attr("label",v).appendTo(menu.find(".project .recents")).click(function(_){
				setProject(v);
			});
		}
		menu.find(".project .open").click(function(_) {
			chooseDirectory(function(dir) {
				if( dir == null ) return;
				if( StringTools.endsWith(dir,"/res") || StringTools.endsWith(dir,"\\res") )
					dir = dir.substr(0,-4);
				setProject(dir);
			});
		});
		menu.find(".project .clear").click(function(_) {
			ideConfig.recentProjects = [];
			config.global.save();
			initMenu();
		});
		menu.find(".project .exit").click(function(_) {
			Sys.exit(0);
		});
		menu.find(".project .clear-local").click(function(_) {
			js.Browser.window.localStorage.clear();
			nw.App.clearCache();
			try sys.FileSystem.deleteFile(Ide.inst.appPath + "/props.json") catch( e : Dynamic ) {};
			untyped chrome.runtime.reload();
		});

		for( r in renderers ) {
			new Element("<menu type='checkbox'>").attr("label", r.name).prop("checked",r == h3d.mat.MaterialSetup.current).appendTo(menu.find(".project .renderers")).click(function(_) {
				if( r != h3d.mat.MaterialSetup.current ) {
					projectConfig.renderer = r.name;
					config.user.save();
					setProject(ideConfig.currentProject);
				}
			});
		}

		// view
		if( !sys.FileSystem.exists(resourceDir) )
			menu.find(".view").remove();
		menu.find(".debug").click(function(_) window.showDevTools());
		var comps = menu.find("[component]");
		for( c in comps.elements() ) {
			var cname = c.attr("component");
			var cl = Type.resolveClass(cname);
			if( cl == null ) error("Missing component class "+cname);
			var state = c.attr("state");
			if( state != null ) try haxe.Json.parse(state) catch( e : Dynamic ) error("Invalid state "+state+" ("+e+")");
			c.click(function(_) {
				open(cname, state == null ? null : haxe.Json.parse(state));
			});
		}

		// database
		var db = menu.find(".database");
		db.find(".dbView").click(function(_) {
			open("hide.view.CdbTable",{});
		});
		db.find(".dbCompress").prop("checked",database.compress).click(function(_) {
			database.compress = !database.compress;
			saveDatabase();
		});
		db.find(".dbExport").click(function(_) {
			var lang = new cdb.Lang(@:privateAccess database.data);
			var xml = lang.buildXML();
			xml = String.fromCharCode(0xFEFF) + xml; // prefix with BOM
			chooseFileSave("export.xml", function(f) {
				if( f != null ) sys.io.File.saveContent(getPath(f), xml);
			});
		});
		function setDiff(f) {
			databaseDiff = f;
			config.user.set("cdb.databaseDiff", f);
			config.user.save();
			loadDatabase();
			hide.comp.cdb.Editor.refreshAll();
			initMenu();
			for( v in getViews(hide.view.CdbTable) )
				v.rebuild();
		}
		db.find(".dbCreateDiff").click(function(_) {
			chooseFileSave("cdb.diff", function(name) {
				if( name == null ) return;
				if( name.indexOf(".") < 0 ) name += ".diff";
				sys.io.File.saveContent(getPath(name),"{}");
				setDiff(name);
			});
		});
		db.find(".dbLoadDiff").click(function(_) {
			chooseFile(["diff"], function(f) {
				if( f == null ) return;
				setDiff(f);
			});
		});
		db.find(".dbCloseDiff").click(function(_) {
			setDiff(null);
		}).attr("disabled", databaseDiff == null ? "disabled" : null);
		db.find(".dbCustom").click(function(_) {
			open("hide.view.CdbCustomTypes",{});
		});

		// layout
		var layouts = menu.find(".layout .content");
		layouts.html("");
		if(projectConfig.layouts == null)
			projectConfig.layouts = [];
		for( l in projectConfig.layouts ) {
			if( l.name == "Default" ) continue;
			new Element("<menu>").attr("label",l.name).addClass(l.name).appendTo(layouts).click(function(_) {
				initLayout(l);
			});
		}
		menu.find(".layout .autosave").click(function(_) {
			ideConfig.autoSaveLayout = !ideConfig.autoSaveLayout;
			config.global.save();
		}).prop("checked",ideConfig.autoSaveLayout);

		menu.find(".layout .saveas").click(function(_) {
			var name = ask("Please enter a layout name:");
			if( name == null || name == "" ) return;
			projectConfig.layouts.push({ name : name, state : saveLayout() });
			config.user.save();
			initMenu();
		});
		menu.find(".layout .save").click(function(_) {
			currentLayout.state = saveLayout();
			config.global.save();
		});

		window.menu = new hide.ui.Menu(menu).root;
	}

	public function openFile( file : String, ?onCreate ) {
		var ext = @:privateAccess hide.view.FileTree.getExtension(file);
		if( ext == null ) return;
		// look if already open
		var path = makeRelative(file);
		for( v in views )
			if( Type.getClassName(Type.getClass(v)) == ext.component && v.state.path == path ) {
				if( v.container.tab != null )
					v.container.parent.parent.setActiveContentItem(v.container.parent);
				return;
			}
		open(ext.component, { path : path }, onCreate);
	}

	public function openSubView<T>( component : Class<hide.ui.View<T>>, state : T, events : {} ) {
		var sharedRefs : Map<Int,Dynamic> = untyped global.sharedRefs;
		if( sharedRefs == null ) {
			sharedRefs = new Map();
			untyped global.sharedRefs = sharedRefs;
		}
		var id = 0;
		while( sharedRefs.exists(id) ) id++;
		sharedRefs.set(id,{ state : state, events : events });
		var compName = Type.getClassName(component);
		nw.Window.open("app.html?subView="+compName+"&sid="+id,{ id : compName });
	}

	public function callParentView( name : String, param : Dynamic ) {
		if( subView != null ) Reflect.callMethod(subView.events,Reflect.field(subView.events,name),[param]);
	}

	public function open( component : String, state : Dynamic, ?onCreate : hide.ui.View<Dynamic> -> Void ) {
		if( state == null ) state = {};

		var c = hide.ui.View.viewClasses.get(component);
		if( c == null )
			throw "Unknown component " + component;

		state.componentName = component;
		for( v in views ) {
			if( v.viewClass == component && haxe.Json.stringify(v.state) == haxe.Json.stringify(state) ) {
				v.activate();
				if( onCreate != null ) onCreate(v);
				return;
			}
		}

		var options = c.options;

		var bestTarget : golden.Container = null;
		for( v in views )
			if( v.defaultOptions.position == options.position ) {
				if( bestTarget == null || bestTarget.width * bestTarget.height < v.container.width * v.container.height )
					bestTarget = v.container;
			}

		var index : Null<Int> = null;
		var target;
		if( bestTarget != null )
			target = bestTarget.parent.parent;
		else {
			target = layout.root.contentItems[0];
			if( target == null ) {
				layout.root.addChild({ type : Row, isClosable: false });
				target = layout.root.contentItems[0];
			}
			target.config.isClosable = false;
		}
		var needResize = options.width != null;
		target.on("componentCreated", function(c) {
			target.off("componentCreated");
			var view : hide.ui.View<Dynamic> = untyped c.origin.__view;
			if( onCreate != null ) onCreate(view);
			if( needResize ) {
				// when opening restricted size after free size
				haxe.Timer.delay(function() {
					view.container.setSize(options.width, view.container.height);
				},0);
			} else {
				// when opening free size after restricted size
				var v0 = views[0];
				if( views.length == 2 && views[1] == view && v0.defaultOptions.width != null )
					haxe.Timer.delay(function() {
						v0.container.setSize(v0.defaultOptions.width, v0.container.height);
					},0);
			}
		});
		var config : golden.Config.ItemConfig = {
			type : Component,
			componentName : component,
			componentState : state
		};

		if( options.position == Left ) index = 0;

		if( index == null )
			target.addChild(config);
		else
			target.addChild(config, index);
	}

	public function message( text : String ) {
		js.Browser.window.alert(text);
	}

	public function confirm( text : String ) {
		return js.Browser.window.confirm(text);
	}

	public function ask( text : String, ?defaultValue = "" ) {
		return js.Browser.window.prompt(text, defaultValue);
	}

	public static var inst : Ide;

	static function main() {
		h3d.pass.ShaderManager.STRICT = false; // prevent errors with bad renderer
		hide.tools.Macros.include(["hide.view","h3d.prim","h3d.scene","h3d.pass","hide.prefab","hrt"]);
		new Ide();
	}

}


class CustomLoader extends hxd.res.Loader {

	var pathKeys = new Map<String,{}>();

	function getKey( path : String ) {
		var k = pathKeys.get(path);
		if( k == null ) {
			k = {};
			pathKeys.set(path, k);
		}
		return k;
	}

	override function loadCache<T:hxd.res.Resource>( path : String, c : Class<T> ) : T {
		var engine = h3d.Engine.getCurrent();
		var i = Std.downcast(@:privateAccess engine.resCache.get(getKey(path)), c);
		if( i == null ) {
			i = Type.createInstance(c, [fs.get(path)]);
			// i = new hxd.res.Image(fs.get(path));
			@:privateAccess engine.resCache.set(getKey(path), i);
		}
		return i;
	}

}
