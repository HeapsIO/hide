package hide;
#if !editor
#error "Non editor code shouldn't depend on hide"
#end

enum MessageKind {
	Info;
	Error;
}

typedef WindowPos = { x : Int, y : Int, w : Int, h : Int, max : Bool };

typedef LayoutState = {
	var content : Any;
	var fullScreen : { name : String, state : Any };
}

class IdeCache {
	public var getTextureCache : Map<String, h3d.mat.Texture> = [];

	public function new() {};
}
@:expose
class Ide extends hide.tools.IdeData {

	public var initializing(default,null) : Bool;

	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	public var isWindows(get, never) : Bool;
	public var isFocused(get, never) : Bool;

	public var isCDB = false;
	public var isDebugger = false;

	public var gamePad(default,null) : hxd.Pad;
	public var localStorage(get,never) : js.html.Storage;

	var window : electron.Window;
	var layout : golden.Layout;

	var currentLayout : { name : String, state : LayoutState };
	var currentFullScreen(default,set) : hide.ui.View<Dynamic>;
	var maximized : Bool;
	var fullscreen : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<hide.ui.View<Dynamic>> = [];
	var lastClosedTabStates : Array<Dynamic> = [];

	var renderers : Array<h3d.mat.MaterialSetup>;
	var subView : { component : String, state : Dynamic };
	var scripts : Map<String,Array<Void->Void>> = new Map();
	var hasReloaded = false;
	public var thumbnailMode : Bool = false;

	var dataTransfer : Map<String, Dynamic> = new Map();

	var hideRoot : hide.Element;
	var statusBar : hide.Element;
	var goldenContainer : hide.Element;
	var statusIcons : hide.Element;

	public var show3DIcons = true;
	public var show3DIconsCategory : Map<hrt.impl.EditorTools.IconCategory, Bool> = new Map();

	static var firstInit = true;

	var customMenus : Array<electron.MenuItem> = [];

	function new() {
		super();
		initPad();
		hxd.System.getClipboardText = () -> electron.Clipboard.get(Text);
		hxd.System.setClipboardText = (text) -> { electron.Clipboard.set(text, Text); return true; };
		var shaderErrors = new Map<String, Bool>();
		h3d.pass.Output.onShaderError = (msg : String, p) -> {
			var text = msg + " (" + p.obj.name + ")";
			var key = p.shader?.id + ":" + text;
			if (!shaderErrors.exists(key)) {
				shaderErrors.set(key, true);
				js.Browser.console.warn(text);
			}
			var s = hide.comp.Scene.getCurrent();
			if (s != null) {
				var nl = msg.indexOf("\n");
				var title = (nl < 0 ? msg : msg.substr(0, nl)) + " (" + p.obj.name + ")";
				@:privateAccess s.setErrorMessage({ title: title, details: nl < 0 ? null : msg.substr(nl + 1), contextObject: p.obj, log: false });
			}
		};
		#if dx12
		hide.tools.NativeMeshTools.init();
		var cacheDir = js.Node.__dirname + "/jsdx";
		h3d.impl.DX12Driver.ENABLE_PSO_CONFIG_CACHE = true;
		h3d.impl.DX12Driver.PSO_CONFIG_CACHE_PATH = h3d.impl.DX12Driver.PSO_CONFIG_CACHE_OUTPUT_PATH = cacheDir + "/psoconfig.dx12";
		h3d.impl.Driver.setShaderCache(new h3d.impl.ShaderCache(cacheDir + "/shadercache.dx12", Binary));
		#end
		isCDB = Sys.getEnv("HIDE_START_CDB") == "1" || electron.App.name == "CDB";
		isDebugger = electron.App.isDebuggerAttached();
		electron.App.onDebuggerChange((b) -> isDebugger = b);

		var thumb = StringTools.contains(js.Browser.window.location.href, "thumbnail");
		if (thumb) {
			thumbnailMode = true;
			readOnlyConfig = true;
		}

		function wait() {
			if( monaco.ScriptEditor == null && !thumbnailMode ) {
				haxe.Timer.delay(wait, 10);
				return;
			}
			startup();
		}
		wait();
	}

	function get_localStorage() {
		return js.Browser.window.localStorage;
	}

	function initPad() {
		gamePad = hxd.Pad.createDummy();
		hxd.Pad.wait((p) -> gamePad = p);
	}

	function thumbnailInit() {
		var generator = @:privateAccess new hide.tools.ThumbnailGenerator();
	}

	function startup() {
		inst = this;
		window = electron.Window.get();
		var cwd = Sys.getCwd();
		for( a in electron.App.argv ) {
			var pre = "--project-dir=";
			if( StringTools.startsWith(a, pre) )
				projectOverride = a.substr(pre.length);
			else if( a == "--default-config" )
				defaultConfig = true;
		}
		initConfig(cwd);
		var current = currentProject;
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
				var state = electron.App.getShared(Std.parseInt(vars.get("sid")));
				subView = { component : sub, state : state };
			}
			// the editor state is written by the main window in another process : it can be read while partially written
			var project = vars.get("project");
			if( thumbnailMode && project != null )
				current = project;
		}

		var xMax = 1;
		var yMax = 1;
		for( s in electron.Screen.screens ) {
			if( s.work_area.x + s.work_area.width > xMax )
				xMax = s.work_area.x + s.work_area.width;
			if( s.work_area.y + s.work_area.height > yMax )
				yMax = s.work_area.y + s.work_area.height;
		}
		if( subView == null && !thumbnailMode ) {
			var wp : WindowPos = globalState.get("windowPos");
			if( wp != null ) {
				if( wp.w > 400 && wp.h > 300 )
					window.resizeTo(wp.w, wp.h);
				if( wp.x >= 0 && wp.y >= 0 && wp.x < xMax && wp.y < yMax)
					window.moveTo(wp.x, wp.y);
				if( wp.max ) {
					window.maximize();
					maximized = true;
				}
			}
		}

		if (!thumbnailMode)
			window.show(true);

		if( !sys.FileSystem.exists(current) || !sys.FileSystem.isDirectory(current) ) {
			if( current != "" ) js.Browser.alert(current+" no longer exists");
			current = cwd;
		}

		setProject(current);
		loadProject();

		if (thumbnailMode) {
			hxd.System.setLoop(mainLoop);
			return;
		}

		js.Browser.document.addEventListener("mousedown", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		js.Browser.document.addEventListener("mousemove", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		js.Browser.window.addEventListener("contextmenu", function(e : js.html.MouseEvent) {
			if (e.defaultPrevented || js.Browser.document.querySelector(".context-menu2:popover-open") != null)
				return;
			e.preventDefault();
			hide.comp.ContextMenu.createFromEvent(e, [{ label : "Reload App", click : reload }]);
		});
		window.on('maximize', function() {
			if(fullscreen) return;
			maximized = true;
			onWindowChange();
		});
		window.on('restore', function() {
			if(fullscreen) return;
			maximized = false;
			onWindowChange();
		});
		window.on('move', function() haxe.Timer.delay(onWindowChange,100));
		window.on('resize', function() haxe.Timer.delay(onWindowChange,100));
		if (!thumbnailMode) {
			window.on('close', function() {
				if( hasReloaded ) return;
				if( !isDebugger )
					for( v in views )
						if( !v.onBeforeClose() )
							return;
				window.close(true);
			});
		}

		window.on("blur", function() { if( h3d.Engine.getCurrent() != null && !hasReloaded ) hxd.Key.initialize(); });

		// handle commandline parameters
		electron.App.onOpen(function(args) {
			if( hasReloaded ) return;
			for( arg in args ) {
				if( StringTools.startsWith(arg, "hide://") || StringTools.startsWith(arg, "cdb://") ) {
					hide.view.RemoteConsoleView.onOpenUri(arg);
					continue;
				}
				if( sys.FileSystem.exists(arg) ) openFile(arg);
			}
		});

		electron.App.onGpuCrash(function(details) {
			if( !hasReloaded ) showGpuCrash(details);
		});

		var body = js.Browser.document.body;
		window.on("focus", function() {
			if(fileExists(databaseFile) && getFileText(databaseFile) != lastDBContent) {
				if(js.Browser.window.confirm(databaseFile + " has changed outside of Hide. Do you want to reload?")) {
					loadDatabase(true);
					hide.comp.cdb.Editor.refreshAll(true);
				};
			}
		});
		function dragFunc(drop : Bool, e : js.html.DragEvent) {
			syncMousePosition(e);
			var view = getViewAt(mouseX, mouseY);
			if (view != null) {
				var handled = drop ? view.onDrop(e) : view.onDrag(e);
				if (handled) {
					e.preventDefault();
					e.stopPropagation();
					return true;
				}
			}
			return false;
		}

		body.ondragenter = function(e:js.html.DragEvent) {
			dragFunc(false, e);
			return false;
		};

		body.ondragover = function(e:js.html.DragEvent) {
			dragFunc(false, e);
			return false;
		};
		body.ondrop = function(e:js.html.DragEvent) {
			if(!dragFunc(true, e)) {
				for( f in e.dataTransfer.files )
					openFile(electron.App.getPathForFile(f));
				e.preventDefault();
			}
			return false;
		}
		body.ondragend = function(e: js.html.DragEvent) {
			for (v in views) {
				if (v != null)
					v.onDragEnd(e);
			}
			e.preventDefault();
			e.stopPropagation();
			return true;
		}

		if( subView != null ) body.className +=" hide-subview";

		// dispatch global keys based on mouse position
		new Element(body).keydown(function(e) {
			var view = getViewAt(mouseX, mouseY);
			if(view != null) view.processKeyEvent(e);
		});

		hrt.impl.EditorTools.setupIconCategories();

		refreshFont();
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
				if (s.window != null) {
					s.window.curMouseX = mouseX;
					s.window.curMouseY = mouseY;
				}
			}
		}
	}

	function get_isWindows() {
		return Sys.systemName() == "Windows";
	}

	function get_isFocused() {
		return js.Browser.document.hasFocus();
	}
	public function focus() {
		window.focus();
	}
	public function blur() {
		window.blur();
	}

	function onWindowChange() {
		if( hasReloaded )
			return;
		var wp : WindowPos = globalState.get("windowPos", { x : 0, y : 0, w : 0, h : 0, max : false });
		wp.max = maximized;
		if( !maximized ) {
			wp.x = window.x;
			wp.y = window.y;
			wp.w = window.width;
			wp.h = window.height;
		}
		if( subView == null )
			globalState.set("windowPos", wp);

		for (v in views)
			v.onResize();
	}

	public function getOrInitTarget(position: hide.ui.View.DisplayPosition) : golden.ContentItem {
		if (layout.root == null)
			return null;
		var target = layout.root.getItemsById(position)[0];
		if (target != null) {
			target.config.content ??= [];
			return target;
		}

		var parent : golden.ContentItem = null;
		var config : golden.Config.ItemConfig;
		var index : Int = null;
		var rootRow = layout.root.contentItems[0];
		switch(position) {
			case Left:
				config = {
					type: Stack,
				};
				parent = rootRow;
				index = 0;
			case Center:
				config = {
					type: Stack,
					isClosable: false,
					width: 1500,
					height: 800,
				};
				parent = getOrInitTarget(MiddleColumnInternal);
				index = 0;
			case Bottom:
				config = {
					type: Stack,
				};
				parent = getOrInitTarget(MiddleColumnInternal);
				index = parent.contentItems.length;
			case Right:
				config = {
					type: Stack,
				};
				parent = rootRow;
				index = parent.contentItems.length;
			case MiddleColumnInternal:
				config = {
					type: Column,
					isClosable: false,
				}
				parent = rootRow;
				index = hxd.Math.iclamp(1, 0, parent.contentItems.length);
		}

		config.id = position;
		parent.addChild(config, index);
		var target = layout.root.getItemsById(position)[0];

		return target;
	}

	function initLayout( ?state : { name : String, state : LayoutState } ) {
		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		var emptyLayout : LayoutState = { content : [], fullScreen : null };

		if( state == null ) {
			var emptyLayout : LayoutState = {
				content: [{type: golden.Config.ItemType.Row, isClosable: false, id: "content_root"}], fullScreen : null,
			};


			var layoutName = isCDB ? "CDB" : "Default";
			var layouts = getLayouts();
			for( i => p in layouts.copy() ) {
				if( p.name == layoutName ) {
					if( p.state.content == null || (p.state.content:Array<Dynamic>)[0]?.id != "content_root") {
						layouts.splice(i, 1);
						continue;
					};
					state = p;
				}
			}

			if( state == null ) {
				state = { name : layoutName, state : emptyLayout };
				layouts.push(state);
			}
			projectState.set("layouts", layouts);
		}

		if( subView != null )
			state = { name : "SubView", state : emptyLayout };

		currentLayout = state;

		var goldenConfig : golden.Config = {
			content: state.state.content,
			settings: {
				// Default to false
				reorderEnabled : currentConfig.get('layout.reorderEnabled', true) == true,
				constrainDragToHeader : currentConfig.get('layout.constrainDragToHeader', true) == true,
				showPopoutIcon : currentConfig.get('layout.showPopoutIcon') == true,
				showMaximiseIcon : currentConfig.get('layout.showMaximiseIcon') == true
			}
		};

		var comps = new Map();
		for( vcl in hide.ui.View.viewClasses )
			comps.set(vcl.name, true);
		function checkRec(i:golden.Config.ItemConfig) {
			if (i.componentName == 'hide.view.FileTree' && i.componentState?.legacy == null) {
				i.componentName = "hide.view.FileBrowser";
				i.componentState = {savedLayout: "SingleTree"};
			}
			switch (i.componentName) {
			case "hide.view.CdbTable", "hide.view.CdbFavorites", "hide.view.CdbCustomTypes":
				i.componentName = "hide.view.cdb." + i.componentName.substr("hide.view.".length);
				i.componentState.componentName = i.componentName;
			default:
			}
			if( i.componentName != null && i.componentState != null && !comps.exists(i.componentName) ) {
				i.componentState.deletedComponent = i.componentName;
				i.componentName = "hide.view.Unknown";
			}
			if( i.content != null ) for( i in i.content ) checkRec(i);
		}
		for( i in goldenConfig.content ) checkRec(i);

		if (hideRoot != null) {
			hideRoot.remove();
			hideRoot = null;
		}
		hideRoot = new Element('<div class="hide-root"></div>').appendTo(new Element("body"));

		goldenContainer = new Element('<div class="golden-layout-root"></div>').appendTo(hideRoot);

		statusBar = new Element('<div class="status-bar"></div>').appendTo(hideRoot);
		statusIcons = new Element('<div id="status-icons"></div>').appendTo(statusBar);
		if( isProjectValid() )
			new hide.comp.GameLauncherWidget(statusBar);

		var commitHash = getGitCommitHashAndDate();
		if (commitHash.length > 0) {
			var driver = #if dx12 "dx12" #else "webgl" #end;
			new Element('<span class="build">hide $driver $commitHash</span>').appendTo(statusBar);
		}

		layout = new golden.Layout(goldenConfig, goldenContainer.get(0));



		var resizeTimer : haxe.Timer = null;
		var observer = new hide.comp.ResizeObserver((elts, observer) -> {
			if (resizeTimer != null) {
				resizeTimer.stop();
			}

			resizeTimer = new haxe.Timer(20);
			resizeTimer.run = () -> {
				var rect = goldenContainer.get(0).getBoundingClientRect();
				layout.updateSize(Std.int(rect.width), Std.int(rect.height));
				resizeTimer.stop();
				resizeTimer = null;
			};
			});
		observer.observe(goldenContainer.get(0));

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

		// remove dangling RefViewers
		for (v in views) {
			if (v.state.componentName == "hide.view.RefViewer") {
				v.close();
			}
		}


		getOrInitTarget(Center);

		// register a global shortcut that break in the debugger
		// on Alt+F1. Usefull to debug UI elements that are temporary
		// Note : the debugger window must be open for this to work
		electron.App.registerGlobalShortcut("Alt+F1", () -> js.Lib.debug());

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
					open("hide.view.cdb.CdbTable",{}, function(v) v.fullScreen = true);
				else
					open("hide.view.FileBrowser",{savedLayout: "SingleTree"}, Left);
			}
			if( firstInit ) {
				firstInit = false;
				for( file in electron.App.argv ) {
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
			fullscreen = true;
			window.maximize();
			window.enterFullscreen();
		} else {
			window.leaveFullscreen();

			// changing fullscreen triggers spurious "restore" events
			haxe.Timer.delay(function() {
				fullscreen = false;
				if(maximized)
					window.maximize();
			}, 150);
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
		if( initializing || !currentConfig.get("hide.autoSaveLayout") || isCDB )
			return;
		currentLayout.state = saveLayout();
		if( subView == null ) projectState.set("layouts", getLayouts());
	}

	function getLayouts() : Array<{ name : String, state : LayoutState }> {
		return projectState.get("layouts", []);
	}

	function saveLayout() : LayoutState {
		return {
			content : layout.toConfig().content,
			fullScreen : currentFullScreen == null ? null : { name : currentFullScreen.viewClass, state : currentFullScreen.state }
		};
	}


	public function setClipboard( data : String, type: electron.Clipboard.ClipboardType = Text ) {
		electron.Clipboard.set(data, type);
	}

	public function setClipboardMultiple( datas: Array<electron.Clipboard.ClipboardData> ) {
		electron.Clipboard.setMultiple(datas);
	}

	public function getClipboard(type: electron.Clipboard.ClipboardType = Text) {
		return electron.Clipboard.get(type);
	}


	public function setData(key: String,  data: Dynamic) {
		dataTransfer.set(key, data);
	}

	public function getData(key: String) {
		return dataTransfer.get(key);
	}

	public function popData(key: String) {
		var d = dataTransfer.get(key);
		dataTransfer.remove(key);
		return d;
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

	public function makeSignature( content : String ) {
		var sign = js.node.Crypto.createHash(js.node.Crypto.CryptoAlgorithm.MD5);
		return sign.update(content).digest("base64");
	}

	public function cleanObject( v : Dynamic ) {
		for( f in Reflect.fields(v) )
			if( Reflect.field(v, f) == null )
				Reflect.deleteField(v, f);
	}

	static var textureCacheKey = "TextureCache";

	public function getHideResPath(basePath:String) {
		return getPath("${HIDE}/res/" + basePath);
	}

	// Get a texture from a file on disk. Cache the results
    public function getTexture(fullPath:String) {
		if (fullPath == null)
			return null;


		var engine = h3d.Engine.getCurrent();
		var cache : IdeCache = cast @:privateAccess engine.resCache.get(IdeCache);
		if(cache == null) {
			cache = new IdeCache();
			@:privateAccess engine.resCache.set(IdeCache, cache);
		}

		var texCache = cache.getTextureCache;

		var tex = texCache[fullPath];
		if (tex != null)
			return tex;

        var data = sys.io.File.getBytes(fullPath);
		var res = hxd.res.Any.fromBytes(fullPath, data);
		tex = res.toImage().toTexture();

		texCache.set(fullPath, tex);
		return tex;
	}

	var showErrors = true;
	var errorWindow :Element = null;
	override function error( e : Dynamic ) {
		if( showErrors ) {
			onIdeError(e);
			if( !js.Browser.window.confirm(e) )
				showErrors = false;
		}

		if (!showErrors) {
			if (errorWindow == null) {
				statusBar.toggleClass("error");

				errorWindow = new Element('<div class="error-suppressed">
					<button class="reload"><i class="icon ico ico-refresh"></i>Reload</button>
					<span>Errors are currently suppressed in the editor. Please save your work and reload.</span>
					</div>
				');

				errorWindow.insertAfter(statusIcons);

				var btnSaveReload = errorWindow.find(".reload");
				btnSaveReload.click(function(_) {
					this.reload();
				});
			}
		}

		js.Browser.console.error(e);
	}

	public function quickError( msg : Dynamic, timeoutSeconds : Float = 5.0 ) {
		js.Browser.console.error(msg);

		globalMessage(msg, Error, timeoutSeconds);
	}

	function loadProject() {
		var dir = currentProject;
		setProgress();
		hxsl.Cache.clear();

		var localDir = sys.FileSystem.exists(resourceDir) ? resourceDir : projectDir;
		var fsconf = currentConfig.get("fs.config", "default");
		hxd.res.Loader.currentInstance = new CustomLoader(new hxd.fs.LocalFileSystem(localDir,fsconf));
		renderers = [
			new hide.Renderer.MaterialSetup("Default"),
			new hide.Renderer.PbrSetup("PBR"),
		];

		var plugins : Array<String> = currentConfig.get("plugins");
		for ( plugin in plugins )
			loadPlugin(plugin, function() {});

		loadDatabase();

		if( currentConfig.get("debug.displayErrors")  ) {
			js.Browser.window.onerror = function(msg, url, line, col, error) {
				if( error == null ) return true; // some internal chrome errors are only a msg, skip
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
			var extraRenderers = currentConfig.get("renderers");
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
			var rendererName : String = projectState.get("renderer", currentConfig.get("defaultRenderer"));
			for( r in renderers ) {
				var name = r.displayName == null ? r.name : r.displayName;
				if( name == rendererName ) {
					render = r;
					break;
				}
			}
			h3d.mat.MaterialSetup.current = render;

			if (thumbnailMode) {
				// after the plugins : the generator scene must use the project renderer
				thumbnailInit();
				return;
			}
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

	public function injectCss(data: String) {
		var head = new Element("head");
		var style = new Element("<style>").appendTo(head);
		style.text(data);
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
				fileWatcher.register(file,reload);
			case "css":
				var e = js.Browser.document.createLinkElement();
				e.addEventListener("load", onLoad);
				e.addEventListener("error", onError);
				e.rel = "stylesheet";
				e.type = "text/css";
				e.href = "file://" + file.split("\\").join("/");
				js.Browser.document.body.appendChild(e);
				fileWatcher.register(file, () -> reloadCss());
			default: error('Unknown plugin type $type for file $file');
		}
	}

	inline function loadScript( file : String, callb : Void -> Void ) {
		loadPlugin(file, callb);
	}

	public function reload() {
		hasReloaded = true;
		fileWatcher.dispose();
		electron.App.unregisterGlobalShortcut("Alt+F1");
		hide.tools.FileManager.onBeforeReload();
		hide.view.RemoteConsoleView.onBeforeReload();
		js.Browser.location.reload();
	}

	public function reloadCss(path: String = null) {
		var css = new js.jquery.JQuery('link[type="text/css"]');
		css.each(function(i, e) : Void {
			var link : js.html.LinkElement = cast e;
			if (path == null || StringTools.contains(link.href, path)) {
				link.href = link.href + "?" + haxe.Timer.stamp();
			}
		});
	}

	public function getCDBContent<T>( sheetName : String ) : Array<T> {
		for( s in database.sheets )
			if( s.name == sheetName ) {
				var s = Reflect.copy(@:privateAccess s.realSheet.sheet);
				s.lines = [for( l in s.lines ) Reflect.copy(l)];
				@:privateAccess cdb.Types.Index.initLines(s);
				return cast s.lines;
			}
		return null;
	}

	public function getUnCachedUrl( path : String ) {
		return "file://" + getPath(path) + "?t=" + fileWatcher.getVersion(path);
	}

	public static var IMG_EXTS = ["jpg", "jpeg", "gif", "png", "raw", "dds", "hdr", "tga"];
	public function chooseImage( onSelect, allowNull=false ) {
		chooseFile(IMG_EXTS, onSelect, allowNull);
	}

	public function chooseFileOptions(onSelect: Null<Array<String>> -> Void, options: {
		?exts : Array<String>,
		?workingDir: String,
		?onlyDirectory: Bool,
		?saveAs: String,
		?isAbsolute: Bool,
		?allowNull: Bool,
		?multiple: Bool,
	} = null) {
		options = options ?? {};

		var defaultPath = null;
		if (options.workingDir != null && options.workingDir != "#MISSING")
			defaultPath = getPath(options.workingDir);
		if (options.saveAs != null)
			defaultPath = defaultPath == null ? options.saveAs : defaultPath + "/" + options.saveAs;
		if (defaultPath != null && isWindows)
			defaultPath = defaultPath.split("/").join("\\");

		function onResult(files: Array<String>) {
			if (files == null) {
				if (options.allowNull) onSelect(null);
				return;
			}
			if (options.isAbsolute != true)
				files = [for (f in files) makeRelative(f)];
			onSelect(files);
		}

		var dialogOptions : electron.Dialog.FileDialogOptions = {
			defaultPath: defaultPath,
			exts: options.exts,
			directory: options.onlyDirectory == true,
			multiple: options.multiple == true,
		};
		if (options.saveAs != null)
			electron.Dialog.saveFile(dialogOptions, (file) -> onResult(file == null ? null : [file]));
		else
			electron.Dialog.openFiles(dialogOptions, onResult);
	}

	/**
		Adds an element to the ide status bar
	**/
	public function addStatusIcon(e: hide.Element) {
		function wait() {
			if( statusIcons == null ) {
				haxe.Timer.delay(wait, 10);
				return;
			}

			var wrapper = new hide.Element('<div class="statusbar-icon"></div>').appendTo(statusIcons);
			wrapper.append(e);
		}
		wait();
	}

	public function chooseFiles( exts : Array<String>, onSelect : Array<String> -> Void, allowNull=false ) {
		chooseFileOptions(onSelect, {exts: exts, allowNull: allowNull, multiple: true});
	}

	public function chooseFile( exts : Array<String>, onSelect : Null<String> -> Void, allowNull = false, workingdir:String = null) {
		chooseFileOptions((files) -> onSelect(files != null ? files.pop() : null), {exts: exts, allowNull: allowNull, workingDir: workingdir});
	}

	public function chooseFileSave( defaultPath : String, onSelect : String -> Void, allowNull=false ) {
		chooseFileOptions((files) -> onSelect(files != null ? files.pop() : null),{saveAs: defaultPath,allowNull: allowNull,});
	}

	public function chooseDirectory( onSelect : String -> Void, ?isAbsolute = false, allowNull=false ) {
		chooseFileOptions((files) -> onSelect(files != null ? files.pop() : null),{isAbsolute: isAbsolute,onlyDirectory: true,allowNull: allowNull,});
	}

	public function search(text : String, ?filesToInclude : Array<String>, ?filesToExclude : Array<String>) : Array<hide.view.RefViewer.Reference> {
		var refs : Array<hide.view.RefViewer.Reference> = [];

		var includeReg : EReg = filesToInclude == null ? null : new EReg('.[.](${[for (i in filesToInclude) '${i}'].join("|")})$', "");
		var exludeReg : EReg = filesToExclude == null ? null : new EReg('.[.](${[for (i in filesToExclude) '${i}'].join("|")})$', "");
		var searchReg = new EReg(text, "g");
		function rec(path : String, file : String) {
			var absPath = path + "/" + file;
			var files = sys.FileSystem.readDirectory(absPath);
			for (f in files) {
				if (f.charAt(0) == "." || (exludeReg != null && exludeReg.match(absPath + "/" + f))) continue;
				if (sys.FileSystem.isDirectory(absPath + "/" + f)) {
					rec(absPath, f);
					continue;
				}

				if (includeReg == null || includeReg.match(absPath + "/" + f)) {
					var content = sys.io.File.getContent(absPath + "/" + f);
					var results = searchReg.split(content);
					if (results.length > 1) {
						var r = { file: f, path: absPath + "/" + f, results: [] };
						var curLen = 0;
						for (idx in 0...(results.length - 1)) {
							var res = results[idx];
							curLen += res.length;
							var contextLength = 15;
							var start = curLen - contextLength + idx * text.length;
							var end = start + text.length + (contextLength * 2);
							r.results.push({ text: content.substring(start, end), goto: () -> {
								var opened = false;

								function getRefInPrefab(rootPrefab: hrt.prefab.Prefab) {
									var hits = [];
									function rec(obj : hrt.prefab.Prefab) {
										for (field in Reflect.fields(obj)) {
											if (Reflect.field(obj, field) == text)
												hits.push(obj);
										}
										for (c in obj.children)
											rec(c);
									}

									rec(rootPrefab);
									return hits[idx];
								}

								var ext = f.substr(f.lastIndexOf('.') + 1);
								switch (ext) {
									case "prefab":
										openFile(absPath + "/" + f, null, (view) -> {
											opened = true;
											var v = Std.downcast(view, hide.view.Prefab);
											v.delaySceneEditor(() -> {
												v.sceneEditor.selectElementsIndirect([getRefInPrefab(@:privateAccess v.data)]);
											});
										});

									case "fx":
										openFile(absPath + "/" + f, null, (view) -> {
											opened = true;
											var v = Std.downcast(view, hide.view.FXEditor);
											v.delaySceneEditor(() -> {
												@:privateAccess v.sceneEditor.selectElementsIndirect([getRefInPrefab(@:privateAccess cast v.data)]);
											});
										});

									case "cdb":
										var hits : Array<{sheet: cdb.Sheet, path: hrt.tools.CdbUtils.Path}> = [];
										for( rootSheet in database.sheets ) {
											// Don't search through datafiles since we already searched them before with prefabs
											if (rootSheet.props.dataFiles != null && rootSheet.lines == null)
												continue;

											function rec(sheet : cdb.Sheet, objs : Array<Dynamic>, path : hrt.tools.CdbUtils.Path, depth : Int) {
												for (idx => obj in objs) {
													for (c in sheet.columns) {
														if (Reflect.field(obj, c.name) == text) {
															var newPath = new hrt.tools.CdbUtils.Path();
															for (p in path)
																newPath.push(p);
															newPath.push(hrt.tools.CdbUtils.PathPart.Prop(c.name));
															hits.push({ sheet: rootSheet, path: newPath });
														}

														var sub = sheet.getSub(c);
														var subObjs: Array<Dynamic> = c.type.match(cdb.Data.ColumnType.TProperties | cdb.Data.ColumnType.TPolymorph) ? [Reflect.field(obj, c.name)] : Reflect.field(obj, c.name);
														if (sub != null && subObjs != null) {
															var newPath = new hrt.tools.CdbUtils.Path();
															for (p in path)
																newPath.push(p);
															newPath.push(hrt.tools.CdbUtils.PathPart.Line(idx, c.name));
															rec(sub, subObjs, newPath, depth+1);
														}
													}
												}
											}

											var path = new hrt.tools.CdbUtils.Path();
											rec(rootSheet, rootSheet.lines, path, 0);
										}


										hide.comp.cdb.Editor.openReference2(hits[idx].sheet, hits[idx].path);

									default:
										hide.tools.IdeData.showFileInExplorer(absPath + "/" + f);
								}
							}});
						}
						refs.push(r);
					}
				}
			}
		}

		var path = projectDir.substr(0, projectDir.lastIndexOf("/"));
		var file = projectDir.substring(projectDir.lastIndexOf("/") + 1);
		rec(path, file);

		return refs;
	}

	/**
		Iterate throught all the strings in the project that could contain a path, replacing
		the value by what `callb` returns. The callb must call `changed()` if it changed the path.
	**/
	public function filterPaths(callb: (ctx : FilterPathContext) -> Void) {
		var context = new FilterPathContext(callb);

		var adaptedFilter = function(name: String) {
			return context.filter(name, context.currentObject);
		}

		function filterContent(content:Dynamic) {
			var visited = new Map<{}, Bool>();
			function browseRec(obj:Dynamic, parent: Dynamic) : Dynamic {
				switch( Type.typeof(obj) ) {
				case TObject:
					if( visited.exists(cast obj)) return null;
					visited.set(cast obj, true);
					for( f in Reflect.fields(obj) ) {
						var v : Dynamic = Reflect.field(obj, f);
						v = browseRec(v, obj);
						if( v != null ) Reflect.setField(obj, f, v);
					}
				case TClass(Array):
					if( visited.exists(cast obj)) return null;
					visited.set(cast obj, true);
					var arr : Array<Dynamic> = obj;
					for( i in 0...arr.length ) {
						var v : Dynamic = arr[i];
						v = browseRec(v, arr);
						if( v != null ) arr[i] = v;
					}
				case TClass(String):
					return context.filter(obj, parent);
				default:
				}
				return null;
			}
			for( f in Reflect.fields(content) ) {
				if (f == "children")
					continue;
				var v = browseRec(Reflect.field(content,f), content);
				if( v != null ) Reflect.setField(content,f,v);
			}
		}

		{
			var currentPath : String = null;
			var currentPrefab: hrt.prefab.Prefab = null;
			context.getRef = () -> {
				var p = currentPath; // needed capture
				var cp = currentPrefab; // needed capture
				return {str: '$p:${cp.getAbsPath()}', goto: () -> openFile(getPath(p), null, (view) -> {
					var pref = Std.downcast(view, hide.view.Prefab);
					if (pref != null) {
						pref.delaySceneEditor(() -> {
							pref.sceneEditor.selectElementsIndirect([cp]);
						});
					}
					else {
						var fx = Std.downcast(view, hide.view.FXEditor);
						fx.delaySceneEditor(() -> {
							@:privateAccess fx.sceneEditor.selectElementsIndirect([cp]);
						});
					}
				})};
			};

			filterPrefabs(function(p:hrt.prefab.Prefab, path: String) {
				context.changed = false;
				currentPath = path;
				currentPrefab = p;
				context.currentObject = p;
				p.source = context.filter(p.source, p);
				var h = p.getHideProps();
				if( h.onResourceRenamed != null )
					h.onResourceRenamed(adaptedFilter);
				else {
					filterContent(p);
				}
				return context.changed;
			});
		}

		{
			var currentPath : String = null;
			context.getRef = () -> {
				var p = currentPath;
				return {str: p, goto : hide.tools.IdeData.showFileInExplorer.bind(getPath(p))};
			}

			filterProps(function(content:Dynamic, path: String) {
				context.changed = false;
				currentPath = path;
				filterContent(content);
				return context.changed;
			});
		}


		context.changed = false;
		var tmpSheets = [];

		var currentSheet : cdb.Sheet = null;
		var currentColumn : String = null;
		var currentObject : Dynamic = null;
		context.getRef = () -> {
			var cs = currentSheet;
			var cc = currentColumn;
			var sheets = cdb.Sheet.getSheetPath(cs, cc);

			var path = hide.comp.cdb.Editor.splitPath({s: sheets, o: currentObject});
			return {str: sheets[0].s.name+"."+path.pathNames.join("."), goto: hide.comp.cdb.Editor.openReference2.bind(sheets[0].s, path.pathParts)};
		};

		for( sheet in database.sheets ) {
			if( sheet.props.dataFiles != null && sheet.lines == null ) {
				// we already updated prefabs, no need to load data files
				tmpSheets.push(sheet);
				@:privateAccess sheet.sheet.lines = [];
			}
			for( c in sheet.columns ) {
				switch( c.type ) {
				case TFile:
					var sheets = cdb.Sheet.getSheetPath(sheet, c.name);
					for( obj in sheet.getObjects() ) {
						currentSheet = sheet;
						currentColumn = c.name;
						currentObject = obj;
						var path = Reflect.field(obj.path[obj.path.length - 1], c.name);
						var v : Dynamic = context.filter(path, obj.path[obj.path.length - 1]);
						if( v != null ) Reflect.setField(obj.path[obj.path.length - 1], c.name, v);
					}
				case TTilePos:
					var sheets = cdb.Sheet.getSheetPath(sheet, c.name);
					for( obj in sheet.getObjects() ) {
						currentSheet = sheet;
						currentColumn = c.name;
						currentObject = obj;

						var tilePos : cdb.Types.TilePos = Reflect.field(obj.path[obj.path.length - 1], c.name);
						if (tilePos != null) {
							var v : Dynamic = context.filter(tilePos.file, tilePos);
							if (v != null) Reflect.setField(tilePos, 'file', v);
						}
					}
				default:
				}
			}
		}
		if( context.changed ) {
			saveDatabase();
			hide.comp.cdb.Editor.refreshAll(true);
		}
		for( sheet in tmpSheets )
			@:privateAccess sheet.sheet.lines = null;

		for (customFilter in customFilepathRefFilters) {
			customFilter(context);
		}
	}

	public var customFilepathRefFilters : Array<(ctx : FilterPathContext) -> Void> = [];

	public function refreshFont() {
		var font = currentConfig.get("hide.useAlternateFont") ? "Verdana" : "Inter";
		var size = currentConfig.get("hide.useAlternateFont") ? "9pt" : "9.5pt";
		js.Browser.document.documentElement.style.setProperty("--default-font", font);
		js.Browser.document.documentElement.style.setProperty("--default-font-size", size);

	}

	public function filterPrefabs( callb : (hrt.prefab.Prefab, path: String) -> Bool) {
		var exts = Lambda.array({iterator : @:privateAccess hrt.prefab.Prefab.extensionRegistry.keys });
		exts.push("prefab");
		var todo = [];
		browseFiles(function(path) {
			var ext = path.split(".").pop();
			if( exts.indexOf(ext) < 0 ) return;
			var prefab = loadPrefab(path);
			var changed = false;
			function filterRec(p) {
				if( callb(p, path) ) changed = true;
				for( ps in p.children )
					filterRec(ps);
			}
			filterRec(prefab);
			if( !changed ) return;
			@:privateAccess todo.push(function() sys.io.File.saveContent(getPath(path), toJSON(prefab.serialize())));
		});
		for( t in todo )
			t();
	}

	public function filterProps( callb : (data: Dynamic, path: String) -> Bool ) {
		var exts = ["props", "json", "prefab"];
		var todo = [];
		browseFiles(function(path) {
			var ext = path.split(".").pop();
			if( exts.indexOf(ext) < 0 ) return;
			try {
				var content = parseJSON(sys.io.File.getContent(getPath(path)));
				var changed = callb(content, path);
				if( !changed ) return;
				todo.push(function() sys.io.File.saveContent(getPath(path), toJSON(content)));
			} catch (e) {};
		});
		for( t in todo )
			t();
	}

	function browseFiles( callb : String -> Void ) {
		function browseRec(path) {
			if( path == ".tmp" ) return;
			if( path == ".backed" ) return;

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

	public function setProgress( ?text : String ) {
		if( text != null ) {
			window.title = text;
			return;
		}
		var title = currentConfig.get("hide.windowTitle");
		window.title = title != null ? title : ((isCDB ? "CastleDB" : "HIDE") + " - " + projectDir);
	}

	public function runCommand(cmd, ?callb:String->Void) {
		var c = cmd.split("%PROJECTDIR%").join(projectDir);
		var slash = isWindows ? "\\" : "/";
		c = c.split("/").join(slash);
		js.node.ChildProcess.exec(c, function(e:js.node.ChildProcess.ChildProcessExecError,_,_) callb(e == null ? null : e.message));
	}

	public function addCustomMenu(item: electron.MenuItem) {
		customMenus.push(item);
	}

	public function initMenu() {

		if( subView != null ) return;

		var menuHTML = "<content>"+new Element("#mainmenu").html() + currentConfig.get("menu.extra")+"</content>";
		var menu = new Element(menuHTML);

		// project
		var recents = recentProjects;
		if( recents.length > 0 )
			menu.find(".project .recents").html("");
		for( v in recents.copy() ) {
			if( !sys.FileSystem.exists(v) ) {
				recents.remove(v);
				globalState.set("recentProjects", recents);
				continue;
			}
			new Element("<menu>").attr("label",v).appendTo(menu.find(".project .recents")).click(function(_){
				var dir = v;
				setProject(dir);
				reload(); // Reload stylesheets
			});
		}
		menu.find(".project .open").click(function(_) {
			chooseDirectory(function(dir) {
				if( dir == null ) return;
				if( StringTools.endsWith(dir,"/res") || StringTools.endsWith(dir,"\\res") )
					dir = dir.substr(0,-4);
				setProject(dir);
				reload();
			}, true);
		});
		menu.find(".project .clear").click(function(_) {
			globalState.set("recentProjects", []);
			initMenu();
		});
		menu.find(".project .exit").click(function(_) {
			electron.App.quit();
		});
		menu.find(".project .clear-local").click(function(_) {
			js.Browser.window.localStorage.clear();
			electron.App.clearCache();
			try sys.FileSystem.deleteFile(userDataPath + "/preferences.json") catch( e : Dynamic ) {};
			try sys.FileSystem.deleteFile(userDataPath + "/editorState.json") catch( e : Dynamic ) {};
			js.Browser.location.reload();
		});
		menu.find(".build-files").click(function(_) {
			hrt.impl.BuildTools.buildAllFiles(resourceDir + "/", function(percent, currentFile) {
				setProgress('($percent%) $currentFile');
			}, function(msg) {
				error(msg);
			}, function(count, errCount) {
				setProgress();
			});
		});

		for( r in renderers ) {
			var name = r.displayName != null ? r.displayName : r.name;
			new Element("<menu type='checkbox'>").attr("label", name).prop("checked",r == h3d.mat.MaterialSetup.current).appendTo(menu.find(".project .renderers")).click(function(_) {
				if( r != h3d.mat.MaterialSetup.current ) {
					projectState.set("renderer", name);
					reload();
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

			var position : hide.ui.View.DisplayPosition = c.attr("position");
			c.click(function(_) {
				open(cname, state == null ? null : haxe.Json.parse(state), position);
			});
		}

		// database
		var db = menu.find(".database");
		db.find(".dbView").click(function(_) {
			open("hide.view.cdb.CdbTable",{});
		});
		db.find(".dbCompress").prop("checked",database.compress).click(function(_) {
			database.compress = !database.compress;
			saveDatabase();
		});
		db.find(".dbExport").click(function(_) {
			hide.comp.cdb.DataFiles.load();
			var lang = new cdb.Lang(@:privateAccess database.data);
			var xml = lang.buildXML();
			xml = String.fromCharCode(0xFEFF) + xml; // prefix with BOM
			chooseFileSave("export.xml", function(f) {
				if( f != null ) sys.io.File.saveContent(getPath(f), xml);
			});
		});
		db.find(".dbImport").click(function(_) {
			chooseFile(["xml"], function(file) {
				hide.comp.cdb.DataFiles.load();
				var lang = new cdb.Lang(@:privateAccess database.data);
				var xml = sys.io.File.getContent(getPath(file));
				lang.apply(xml);
				saveDatabase(true);

				for( file in @:privateAccess hide.comp.cdb.DataFiles.watching.keys() ) {
					if( sys.FileSystem.isDirectory(getPath(file)) )
						continue;
					var p = loadPrefab(file);
					lang.applyPrefab(p);
					savePrefab(file, p);
				}

				hide.comp.cdb.Editor.refreshAll();
				message("Import completed");
			});
		});

		var proofing = projectState.get("dbProofread") == true;
		db.find(".dbProofread").prop("checked", proofing).click(function(_) {
			projectState.set("dbProofread", !proofing);
			for( v in getViews(hide.view.cdb.CdbTable) )
				v.applyProofing();
			initMenu();
		});

		function setDiff(f) {
			databaseDiff = f;
			projectUserConfig.set("cdb.databaseDiff", f);
			loadDatabase();
			hide.comp.cdb.Editor.refreshAll();
			initMenu();
			for( v in getViews(hide.view.cdb.CdbTable) )
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
			open("hide.view.cdb.CdbCustomTypes",{});
		});
		db.find(".dbFormulasEnable").prop("checked",currentConfig.get("hide.enableDBFormulas")).click(function(_) {
			userConfig.set("hide.enableDBFormulas", !currentConfig.get("hide.enableDBFormulas"));
			hide.comp.cdb.Editor.refreshAll();
		});
		db.find(".dbFormulas").click(function(_) {
			open("hide.comp.cdb.FormulasView",{ path : currentConfig.get("cdb.formulasFile") });
		});

		// Categories
		{
			function setCategories( cats : Array<String> ) {
				projectState.set("dbCategories", cats);
				for( v in getViews(hide.view.cdb.CdbTable) )
					v.applyCategories(cats);
				initMenu();
			}
			var visibleCats : Array<String> = projectState.get("dbCategories");
			var allCats = hide.comp.cdb.Editor.getCategories(database);
			var showAll = db.find(".dbCatShowAll");
			for(cat in allCats) {
				var isShown = visibleCats == null || visibleCats.indexOf(cat) >= 0;
				new Element("<menu type='checkbox'>").attr("label",cat).prop("checked", isShown).insertBefore(showAll).click(function(_){
					var cats = visibleCats ?? allCats.copy(); // Init with all cats
					if(isShown)
						cats.remove(cat);
					else
						cats.push(cat);
					setCategories(cats);
				});
			}
			new Element("<separator>").insertBefore(showAll);

			db.find(".dbCatShowAll").click(function(_) {
				setCategories(null);
			});
			db.find(".dbCatHideAll").click(function(_) {
				setCategories([]);
			});
		}

		// layout
		var layouts = menu.find(".layout .content");
		layouts.html("");
		for( l in getLayouts() ) {
			if( l.name == "Default" ) continue;
			new Element("<menu>").attr("label",l.name).addClass(l.name).appendTo(layouts).click(function(_) {
				initLayout(l);
			});
		}
		menu.find(".layout .autosave").click(function(_) {
			userConfig.set("hide.autoSaveLayout", !currentConfig.get("hide.autoSaveLayout"));
		}).prop("checked",currentConfig.get("hide.autoSaveLayout"));

		menu.find(".layout .saveas").click(function(_) {
			var name = ask("Please enter a layout name:");
			if( name == null || name == "" ) return;
			var layouts = getLayouts();
			layouts.push({ name : name, state : saveLayout() });
			projectState.set("layouts", layouts);
			initMenu();
		});
		menu.find(".layout .save").click(function(_) {
			currentLayout.state = saveLayout();
			projectState.set("layouts", getLayouts());
		});

		menu.find(".capture-transparentBG").click(function(_) {
					var currentView : hide.ui.View<Dynamic> = null;
			for (v in views) {
				if (v.isActive())
					currentView = v;
			}

			var scene : hide.comp.Scene = null;
			var modelView = Std.downcast(currentView, hide.view.Model);
			if (modelView != null)
				scene = @:privateAccess modelView.scene;
			var prefabView = Std.downcast(currentView, hide.view.Prefab);
			if (prefabView != null)
				scene = @:privateAccess prefabView.scene;
			var fxView = Std.downcast(currentView, hide.view.FXEditor);
			if (fxView != null)
				scene = @:privateAccess fxView.scene;

			if (scene == null) {
				quickError("Active view isn't capturable");
				return;
			}

			chooseFileSave("capture.png", (path) -> {
				var renderer = Std.downcast(scene.s3d.renderer, h3d.scene.pbr.Renderer);
				if(renderer == null) {
					quickError("Renderer not available for screen capture");
					return;
				}

				var textureRes = currentConfig.get("hide.screenCaptureResolution");
				var renderTexture = new h3d.mat.Texture(Std.int(textureRes * scene.s3d.camera.screenRatio), textureRes, [Target], RGBA);
				renderTexture.depthBuffer = new h3d.mat.Texture(renderTexture.width, renderTexture.height, Depth24Stencil8);
				renderTexture.clear(0, 0);
				var prevBackgroundColor = scene.engine.backgroundColor;
				var prevSkyMode = renderer.skyMode;
				var props : h3d.scene.pbr.Renderer.RenderProps = renderer.props;
				var prevForceDirectDiscard = props.forceDirectDiscard;

				// setOutputTarget() restores the size of the default depth, not the scene's (dx12 : shared driver)
				var prevWidth = scene.engine.width, prevHeight = scene.engine.height;
				scene.engine.backgroundColor &= 0x00FFFFFF;
				scene.s3d.setOutputTarget(scene.engine, renderTexture);
				renderer.skyMode = Hide;
				props.forceDirectDiscard = true;

				scene.s3d.render(scene.engine);
				scene.s3d.setOutputTarget();
				@:privateAccess scene.engine.width = prevWidth;
				@:privateAccess scene.engine.height = prevHeight;

				scene.engine.backgroundColor = prevBackgroundColor;
				renderer.skyMode = prevSkyMode;
				props.forceDirectDiscard = prevForceDirectDiscard;

				var pixels = renderTexture.capturePixels();
				var absPath = getPath(path);
				sys.io.File.saveBytes(absPath, pixels.toPNG());
				quickMessage('Screen capture saved at ${path}');
			});
		});

		menu.find(".screen-capture").click(function(_) {
			var currentView : hide.ui.View<Dynamic> = null;
			for (v in views) {
				if (v.isActive())
					currentView = v;
			}

			var scene : hide.comp.Scene = null;
			var modelView = Std.downcast(currentView, hide.view.Model);
			if (modelView != null)
				scene = @:privateAccess modelView.scene;
			var prefabView = Std.downcast(currentView, hide.view.Prefab);
			if (prefabView != null)
				scene = @:privateAccess prefabView.scene;
			var fxView = Std.downcast(currentView, hide.view.FXEditor);
			if (fxView != null)
				scene = @:privateAccess fxView.scene;

			if (scene == null) {
				quickError("Active view isn't capturable");
				return;
			}

			chooseFileSave("capture.png", (path) -> {
				var textureRes = currentConfig.get("hide.screenCaptureResolution");


				var renderTexture = new h3d.mat.Texture(Std.int(textureRes * scene.s3d.camera.screenRatio), textureRes, [Target]);
				renderTexture.depthBuffer = new h3d.mat.Texture(renderTexture.width, renderTexture.height, Depth24Stencil8);
				var prevWidth = scene.engine.width, prevHeight = scene.engine.height;
				scene.s3d.setOutputTarget(scene.engine, renderTexture);
				scene.s3d.render(scene.engine);
				scene.s3d.setOutputTarget();
				@:privateAccess scene.engine.width = prevWidth;
				@:privateAccess scene.engine.height = prevHeight;

				var pixels = renderTexture.capturePixels();
				var absPath = getPath(path);
				sys.io.File.saveBytes(absPath, pixels.toPNG());
				quickMessage('Screen capture saved at ${path}');
			});
		});

		// analysis
		var analysis = menu.find(".analysis");
		analysis.find(".memprof").click(function(_) {
			#if (hashlink >= "1.15.0")
			open("hide.view.MemProfiler",{});
			#else
			quickMessage("Memory Profiler not available. Please update hashlink to version 1.15.0 or later.");
			#end
		});
		analysis.find(".remoteconsole").click(function(_) {
			open("hide.view.RemoteConsoleView",{});
		});
		analysis.find(".devtools").click(function(_) {
			open("hide.view.DevTools",{});
		});
		analysis.find(".gpudump").click(function(_) {
			var path = hide.tools.MemDump.gpudump();
			quickMessage('Gpu mem dumped at ${path}.');
		});

		var settings = menu.find(".settings");
		settings.find('.user-settings').click(function(_) {
			open("hide.view.settings.UserSettings", {});
		});
		settings.find('.project-settings').click(function(_) {
			open("hide.view.settings.ProjectSettings", {});
		});

		var finalMenu = new hide.ui.Menu(menu).root;
		for (custom in customMenus) {
			finalMenu.append(custom);
		}

		window.menu = finalMenu;
	}

	public function showFileInResources(path: String) {
		var filebrowsers = getViews(hide.view.FileBrowser);
		for (filebrowser in filebrowsers) {
			if (@:privateAccess filebrowser.fancyTree == null)
				filebrowser.onDisplay();
			filebrowser.activate();
			filebrowser.reveal(path);
		}
	}

	public function openFile( file : String, ?onCreate, ?onOpen) {
		var ext = Extension.getExtension(file);
		if( ext == null ) return;
		// look if already open
		var path = makeRelative(file);
		for( v in views )
			if( Type.getClassName(Type.getClass(v)) == ext.component && v.state.path == path ) {
				if( v.container.tab != null ) {
					v.container.parent.parent.setActiveContentItem(v.container.parent);
					if (onOpen != null ) onOpen(v);
				}
				return;
			}
		open(ext.component, { path : path }, onCreate, onOpen);
	}

	public function openSubView<T>( component : Class<hide.ui.View<T>>, state : T, events : {} ) {
		// state is sent to the sub window, events are called back through IPC
		if( subViewEvents == null ) {
			subViewEvents = [];
			electron.Window.onOpenerCall(function(name, param) {
				for( events in subViewEvents ) {
					var f = Reflect.field(events, name);
					if( f != null ) Reflect.callMethod(events, f, [param]);
				}
			});
		}
		if( subViewEvents.indexOf(events) < 0 ) subViewEvents.push(events);
		var id = electron.App.setShared(state);
		var compName = Type.getClassName(component);
		electron.Window.open("app.html?subView="+compName+"&sid="+id);
	}

	var subViewEvents : Array<{}>;

	public function callParentView( name : String, param : Dynamic ) {
		if( subView != null ) electron.Window.callOpener(name, param);
	}

	public function closeInspector() {
		var inspector = layout.root.getItemsById("inspector")[0];
		if (inspector != null) {
			inspector.remove();
		}
	}

	public function open( component : String, state : Dynamic, ?onCreate : hide.ui.View<Dynamic> -> Void, ?onOpen : hide.ui.View<Dynamic> -> Void, ?positionOverride: hide.ui.View.DisplayPosition ) {
		if (layout.root == null)
			return;
		if( state == null ) state = {};

		var viewConfig = hide.ui.View.viewClasses.get(component);
		if( viewConfig == null )
			throw "Unknown component " + component;

		state.componentName = component;
		for( v in views ) {
			if( v.viewClass == component && haxe.Json.stringify(v.state) == haxe.Json.stringify(state) ) {
				v.activate();
				if( onCreate != null ) onCreate(v);
				if ( onOpen != null ) onOpen(v);
				return;
			}
		}

		var options = viewConfig.options;

		var target = getOrInitTarget(positionOverride ?? options.position ?? Center);

		var needResize = options.width != null;
		target.on("componentCreated", function(c) {
			target.off("componentCreated");
			var view : hide.ui.View<Dynamic> = untyped c.origin.__view;
			if( onCreate != null ) onCreate(view);
			if ( onOpen != null ) onOpen(view);
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
			componentState : state,
		};

		if (options.id != null) {
			config.id = options.id;
		}

		target.addChild(config);
	}

	public function reopenLastClosedTab() {
		var state = lastClosedTabStates.pop();
		if( state != null && state.componentName != null ) {
			open(state.componentName, state);
		}
	}

	var deduplicateMessages : Map<String, {element: Element, timer: haxe.Timer}> = [];

	public function globalMessage(message: String, kind: MessageKind, timeoutSeconds : Float = 5.0) {
		var str = StringTools.htmlEscape(Std.string(message));
		str = StringTools.replace(str, "\n", "<br/>");

		var element = switch(kind) {
			case Info:
				new Element('
				<div class="message">
					<div class="icon ico ico-info-circle"></div>
					<div class="text">${str}</div>
				</div>');
			case Error:
				new Element('
				<div class="message error">
					<div class="icon ico ico-warning"></div>
					<div class="text">${str}</div>
				</div>');
		}

		final mergeMessageDelayMs = 200;

		function timeMessage(element: Element) {
			var timer = haxe.Timer.delay(() -> {
				deduplicateMessages.remove(str);
				haxe.Timer.delay(() -> {
					element.get(0).ontransitionend = function(_){
						element.remove();
					};
					element.removeClass("show");
				}, Std.int(timeoutSeconds * 1000.0 - mergeMessageDelayMs));
			}, mergeMessageDelayMs);
			deduplicateMessages.set(str, {element: element, timer: timer});
		}

		var prev = deduplicateMessages.get(str);
		// if there is already a message with the same message as ours, restart it
		if (prev != null) {
			prev.timer.stop();
			deduplicateMessages.remove(str);
			timeMessage(prev.element);
			return;
		}

		var body = new Element('body');
		var messages = body.find("#message-container");
		if (messages.length == 0) {
			messages = new Element('<div id="message-container"></div>');
			body.append(messages);
		}

		messages.append(element);

		haxe.Timer.delay(() -> {
			element.addClass("show");
		}, 10);

		timeMessage(element);
	}

	public function quickMessage( text : String, timeoutSeconds : Float = 5.0 ) {
		js.Browser.console.log(text);

		globalMessage(text, Info, timeoutSeconds);
	}

	public function message( text : String ) {
		js.Browser.window.alert(text);
	}

	public function confirm( text : String ) {
		return js.Browser.window.confirm(text);
	}

	public function ask( text : String, ?defaultValue = "" ) {
		return electron.Dialog.prompt(text, defaultValue);
	}

	var delayedSvnStatusCallbacks : Array<(files : Array<String>) -> Void> = null;

	function onSvnStatusFinished(callbacks: Array<(files : Array<String>) -> Void>, error: Dynamic, stdOut: String, stderr: String) {
		var modifiedFiles : Array<String> = [];
		var outputs : Array<String> = stdOut.split("\r\n");
		for (o in outputs) {
			if (o.length == 0)
				continue;

			o = StringTools.replace(o, '\\', "/");
			var file = getPath(o.substr(o.indexOf("res/") + 4));
			modifiedFiles.push(file);
		}
		for (callback in callbacks) {
			callback(modifiedFiles);
		}

		if (delayedSvnStatusCallbacks != null && delayedSvnStatusCallbacks.length > 0) {
			var oldCallbacks = delayedSvnStatusCallbacks;
			delayedSvnStatusCallbacks = [];
			execSvnCommand(onSvnStatusFinished.bind(oldCallbacks));
		} else {
			delayedSvnStatusCallbacks = null;
		}
	}

	function execSvnCommand(callback: (error: Dynamic, stdOut: String, stderr: String) -> Void) {
		js.node.ChildProcess.exec('svn status', { cwd: projectDir }, callback);
	}

	public function getSVNModifiedFiles(callback: (files : Array<String>) -> Void) : Void{
		if (!isSVNAvailable())
			throw "SVN not available";

		if (delayedSvnStatusCallbacks == null) {
			delayedSvnStatusCallbacks = [];
			execSvnCommand(onSvnStatusFinished.bind([callback]));
		} else {
			hide.tools.Extensions.ArrayExtensions.pushUnique(delayedSvnStatusCallbacks, callback);
		}
	}

	public function isSVNAvailable() {
		return js.node.ChildProcess.spawnSync("svn",["--version"]).status == 0 &&
		js.node.ChildProcess.spawnSync("where.exe", ["TortoiseProc.exe"]).status == 0 &&
		js.node.ChildProcess.spawnSync("svn", ["info", getPath(projectDir)]).status == 0;
	}

	public static dynamic function onIdeError(e: Dynamic) {}

	public static var inst : Ide;

	static function main() {
		h3d.impl.RenderContext.STRICT = false; // prevent errors with bad renderer
		new Ide();
	}


	public static function getGitCommitHashAndDate():String {

		// Check if there is changes in git. If thats the case, we are certainly on a dev machine
		var out = "";
		try {
			out = js.node.ChildProcess.execSync('git status --porcelain=v1');
		} catch (_) {
			return "";
		}

		if (out.length > 0) {
			return "dev";
		}

		try {
			out = js.node.ChildProcess.execSync('git log --pretty=format:"%h(%cs)" -n 1');
		} catch (_) {
			return "";
		}

		return out;
	}

	var gpuCrash : hide.comp.Modal.Modal2;

	/** the GPU process was lost (TDR, driver crash) : the display recovers, but it should be reported **/
	function showGpuCrash( details : Dynamic ) {
		if( gpuCrash != null ) return;
		gpuCrash = new hide.comp.Modal.Modal2(new Element("body"), "The GPU crashed", null, false);
		gpuCrash.element.addClass("gpu-crash");
		var panel = new Element('<div>
			<p>The GPU process of Chromium was lost (${details.reason}, exit code ${details.exitCode}). The display has recovered, but this crash should be reported.</p>
			<p>Create a report and send it to the tools programmers, with what you were doing.</p>
			<p class="path"></p>
			<div class="buttons">
				<fancy-button class="create"><span class="label">Create report</span></fancy-button>
				<fancy-separator></fancy-separator>
				<fancy-button class="close"><span class="label">Close</span></fancy-button>
			</div>
		</div>').appendTo(gpuCrash.content);
		panel.find(".create").click(function(_) {
			var driver = #if dx12 "dx12" #else "webgl" #end;
			electron.App.createCrashReport('hide $driver ${getGitCommitHashAndDate()}\nProject : $currentProject\n').then(
				(file) -> panel.find(".path").text("Report created : " + file),
				(e) -> panel.find(".path").text("Report failed : " + e)
			);
		});
		panel.find(".close").click(function(_) {
			gpuCrash.close();
			gpuCrash = null;
		});
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
			// streamed images are registered in a static list never purged : thumbnails load at full resolution
			var img = hide.Ide.inst.thumbnailMode ? Std.downcast((i : hxd.res.Resource), hxd.res.Image) : null;
			if( img != null )
				img.disableStreaming = true;
			@:privateAccess engine.resCache.set(getKey(path), i);
		}
		return i;
	}

	override function cleanCache() {
		var engine = h3d.Engine.getCurrent();
		for (k in pathKeys) {
			var res = Std.downcast(@:privateAccess engine.resCache.get(k), hxd.res.Resource);
			if (res == null)
				continue;
			@:privateAccess engine.resCache.remove(k);
			res.entry.unwatch(engine.id);
			var img = Std.downcast(res, hxd.res.Image);
			if (img != null)
				@:privateAccess img.tex?.dispose();
		}
		super.cleanCache();
	}

}

@:allow(hide.Ide)
class FilterPathContext {
	public var valueCurrent: String;
	public var currentObject: Dynamic;
	var valueChanged: String;

	public var filterFn: (FilterPathContext) -> Void;

	var changed = false;
	public function new(filterFn: (FilterPathContext) -> Void) {
		this.filterFn = filterFn;
	};

	public function change(newValue) : Void {
		changed = true;
		valueChanged = newValue;
	}

	public function filter(valueCurrent: String, obj: Dynamic) {
		this.valueCurrent = valueCurrent;
		this.currentObject = obj;
		valueChanged = null;
		var prevChanged = changed;
		changed = false;
		filterFn(this);
		var res = changed ? valueChanged : valueCurrent;
		changed = prevChanged || changed;
		return res;
	}

	public var getRef : () -> {str: String, ?goto: () -> Void};
}
