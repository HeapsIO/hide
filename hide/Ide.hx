package hide;

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

	public var shaderLoader : hide.tools.ShaderLoader;
	public var isCDB = false;
	public var isDebugger = false;

	public var gamePad(default,null) : hxd.Pad;
	public var localStorage(get,never) : js.html.Storage;

	var window : nw.Window;
	var saveMenu : nw.Menu;
	var layout : golden.Layout;

	var currentLayout : { name : String, state : Config.LayoutState };
	var currentFullScreen(default,set) : hide.ui.View<Dynamic>;
	var maximized : Bool;
	var fullscreen : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<hide.ui.View<Dynamic>> = [];
	var lastClosedTabStates : Array<Dynamic> = [];

	var renderers : Array<h3d.mat.MaterialSetup>;
	var subView : { component : String, state : Dynamic, events : {} };
	var scripts : Map<String,Array<Void->Void>> = new Map();
	var hasReloaded = false;
	public var thumbnailMode : Bool = false;

	var dataTransfer : Map<String, Dynamic> = new Map();

	var hideRoot : hide.Element;
	var statusBar : hide.Element;
	var goldenContainer : hide.Element;
	var statusIcons : hide.Element;

	var breakShortcut : Dynamic;

	public var show3DIcons = true;
	public var show3DIconsCategory : Map<hrt.impl.EditorTools.IconCategory, Bool> = new Map();

	static var firstInit = true;

	var customMenus : Array<nw.MenuItem> = [];

	var filePickerElement : hide.Element;

	function new() {
		super();
		initPad();
		isCDB = Sys.getEnv("HIDE_START_CDB") == "1" || nw.App.manifest.name == "CDB";
		isDebugger = Sys.getEnv("HIDE_DEBUG") == "1";

		var thumb = StringTools.contains(js.Browser.window.location.href, "thumbnail");
		if (thumb) {
			thumbnailMode = true;
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

	override function getAppDataPath() {
		return nw.App.dataPath;
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
		window = nw.Window.get();
		var cwd = Sys.getCwd();
		initConfig(cwd);
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

		nw.Screen.Init();
		var xMax = 1;
		var yMax = 1;
		for( s in nw.Screen.screens ) {
			if( s.work_area.x + s.work_area.width > xMax )
				xMax = s.work_area.x + s.work_area.width;
			if( s.work_area.y + s.work_area.height > yMax )
				yMax = s.work_area.y + s.work_area.height;
		}
		if( subView == null ) {
			var wp = ideConfig.windowPos;
			if( wp != null ) {
				if( wp.w > 400 && wp.h > 300 )
					window.resizeBy(wp.w - Std.int(window.window.outerWidth), wp.h - Std.int(window.window.outerHeight));
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

		if( config.global.get("hide") == null )
			error("Failed to load defaultProps.json");

		if( !sys.FileSystem.exists(current) || !sys.FileSystem.isDirectory(current) ) {
			if( current != "" ) js.Browser.alert(current+" no longer exists");
			current = cwd;
		}

		setProject(current);
		loadProject();

		if (thumbnailMode) {
			thumbnailInit();
			hxd.System.setLoop(mainLoop);
			return;
		}

		window.window.document.addEventListener("mousedown", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		window.window.document.addEventListener("mousemove", function(e) {
			mouseX = e.x;
			mouseY = e.y;
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
		nw.App.on("open", function(cmd) {
			if( hasReloaded ) return;
			~/"([^"]+)"/g.map(cmd, function(r) {
				var file = r.matched(1);
				if( sys.FileSystem.exists(file) ) openFile(file);
				return "";
			});
		});

		var body = window.window.document.body;
		window.on("focus", function() {
			// handle cancel on type=file

			if (filePickerElement != null && filePickerElement.data("allownull") != null) {
				haxe.Timer.delay(() -> {
					if (filePickerElement != null) {
						filePickerElement.change();
					}
				}, 100);
			}

			if(fileExists(databaseFile) && getFileText(databaseFile) != lastDBContent) {
				if(js.Browser.window.confirm(databaseFile + " has changed outside of Hide. Do you want to reload?")) {
					loadDatabase(true);
					hide.comp.cdb.Editor.refreshAll(true);
				};
			}
		});
		function dragFunc(drop : Bool, e:js.html.DragEvent) {
			syncMousePosition(e);
			var view = getViewAt(mouseX, mouseY);
			var items : Array<String> = [for(f in e.dataTransfer.files) Reflect.field(f, "path")];
			if (e.dataTransfer.types.contains("application/x.filemove")) {
				var data = e.dataTransfer.getData("application/x.filemove");
				// when in the middle of a drag (and not a drop) getData return nothing
				if (data.length > 0) {
					var moreItems : Array<String> = haxe.Json.parse(data);
					items = items.concat(moreItems);
				}
			}
			if(view != null && view.onDragDrop(items, drop, e)) {
				e.preventDefault();
				e.stopPropagation();
				return true;
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
					openFile(Reflect.field(f,"path"));
				e.preventDefault();
			}
			return false;
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

		for (v in views)
			v.onResize();
	}

	public function getOrInitTarget(position: hide.ui.View.DisplayPosition) : golden.ContentItem {
		if (layout.root == null)
			return null;
		var target = layout.root.getItemsById(position)[0];
		if (target != null)
			return target;

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

	function initLayout( ?state : { name : String, state : Config.LayoutState } ) {
		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		var emptyLayout : Config.LayoutState = { content : [], fullScreen : null };

		if( state == null ) {
			var emptyLayout : Config.LayoutState = {
				content: [{type: golden.Config.ItemType.Row, isClosable: false, id: "content_root"}], fullScreen : null,
			};


			var layoutName = isCDB ? "CDB" : "Default";
			for( i => p in projectConfig.layouts.copy() ) {
				if( p.name == layoutName ) {
					if( p.state.content == null || (p.state.content:Array<Dynamic>)[0]?.id != "content_root") {
						projectConfig.layouts.splice(i, 1);
						continue;
					};
					state = p;
				}
			}

			if( state == null ) {
				state = { name : layoutName, state : emptyLayout };
				projectConfig.layouts.push(state);
			}
		}

		if( subView != null )
			state = { name : "SubView", state : emptyLayout };

		currentLayout = state;

		var goldenConfig : golden.Config = {
			content: state.state.content,
			settings: {
				// Default to false
				reorderEnabled : config.user.get('layout.reorderEnabled', true) == true,
				constrainDragToHeader : config.user.get('layout.constrainDragToHeader', true) == true,
				showPopoutIcon : config.user.get('layout.showPopoutIcon') == true,
				showMaximiseIcon : config.user.get('layout.showMaximiseIcon') == true
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

		var commitHash = getGitCommitHashAndDate();
		if (commitHash.length > 0) {
			new Element('<span class="build">hide $commitHash</span>').appendTo(statusBar);
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

		getOrInitTarget(Center);

		// register a global shortcut that break in the debugger
		// on Alt+F1. Usefull to debug UI elements that are temporary
		// Note : the debugger window must be open for this to work
		{
			var option = {
				key: "Alt+F1",
				active: () -> {
					js.Lib.debug();
				}
			};

			breakShortcut = js.Syntax.construct("nw.Shortcut", option);
			untyped nw.App.registerGlobalHotKey(breakShortcut);
		}

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
					open("hide.view.FileBrowser",{savedLayout: "SingleTree"}, Left);
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
			fullscreen = true;
			window.maximize();
			saveMenu = window.menu;
			window.menu = null;
			window.enterFullscreen();
		} else {
			window.menu = saveMenu;
			window.leaveFullscreen();

			// NWJS bug: changing fullscreen triggers spurious "restore" events
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
		if( initializing || !ideConfig.autoSaveLayout || isCDB )
			return;
		currentLayout.state = saveLayout();
		if( subView == null ) this.config.user.save();
	}

	function saveLayout() : Config.LayoutState {
		return {
			content : layout.toConfig().content,
			fullScreen : currentFullScreen == null ? null : { name : currentFullScreen.viewClass, state : currentFullScreen.state }
		};
	}


	public function setClipboard( data : String, type: nw.Clipboard.ClipboardType = Text ) {
		nw.Clipboard.get().set([{data: data, type: type }]);
	}

	public function setClipboardMultiple( datas: Array<nw.Clipboard.ClipboardData> ) {
		nw.Clipboard.get().set(datas);
	}

	public function getClipboard(type: nw.Clipboard.ClipboardType = Text) {
		return nw.Clipboard.get().get(type);
	}


	public function setData(key: String,  data: Dynamic) {
		dataTransfer.set(key, data);
	}

	public function getData(key: String) {
		return dataTransfer.get(key);
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
		var str = StringTools.htmlEscape(Std.string(msg));
		str = StringTools.replace(str, "\n", "<br/>");
		var e = new Element('
		<div class="message error">
			<div class="icon ico ico-warning"></div>
			<div class="text">${str}</div>
		</div>');

		js.Browser.console.error(msg);

		globalMessage(e, timeoutSeconds);
	}

	function loadProject() {
		var dir = ideConfig.currentProject;
		setProgress();
		shaderLoader = new hide.tools.ShaderLoader();
		hxsl.Cache.clear();

		var localDir = sys.FileSystem.exists(resourceDir) ? resourceDir : projectDir;
		var fsconf = config.current.get("fs.config", "default");
		hxd.res.Loader.currentInstance = new CustomLoader(new hxd.fs.LocalFileSystem(localDir,fsconf));
		hxd.res.Image.ASYNC_LOADER = new hxd.impl.AsyncLoader.NodeLoader();
		renderers = [
			new hide.Renderer.MaterialSetup("Default"),
			new hide.Renderer.PbrSetup("PBR"),
		];

		var plugins : Array<String> = config.current.get("plugins");
		for ( plugin in plugins )
			loadPlugin(plugin, function() {});

		loadDatabase();

		if( config.project.get("debug.displayErrors")  ) {
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
			for( r in renderers ) {
				var name = r.displayName == null ? r.name : r.displayName;
				if( name == projectConfig.renderer ) {
					render = r;
					break;
				}
			}
			h3d.mat.MaterialSetup.current = render;

			if (thumbnailMode) {
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
		untyped nw.App.unregisterGlobalHotKey(breakShortcut);
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

		function callback() {
			if (filePickerElement != null)
				filePickerElement.remove();

			var args : Array<String> = [];

			if (options.allowNull == true)
				args.push("data-allownull='true'");
			if (options.saveAs != null)
				args.push('nwsaveas="${options.saveAs}"');
			if (options.exts != null)
				args.push('accept="${[for( e in options.exts ) "."+e].join(",")}"');
			if (options.onlyDirectory == true)
				args.push("nwdirectory");
			if (options.multiple == true)
				args.push('multiple="multiple"');
			if (options.workingDir != null && options.workingDir != "#MISSING") {
				var pathArray = getPath(options.workingDir).split("/");
				var c = isWindows ? "\\" : "/";
				var workingDirPath = pathArray.join(c);
				args.push('nwworkingdir="$workingDirPath"');
			}

			var argsString = args.join(" ");

			var buildString = '<input type="file" style="visibility:hidden; position:fixed; top:0px;" value="" $argsString/>';

			filePickerElement = new Element(buildString).appendTo(window.window.document.body);

			filePickerElement.change(function(_) {
				var file = filePickerElement.val();
				filePickerElement.remove();
				filePickerElement = null;
				if( file == "" && !options.allowNull ) return;
				if (file == "") {
					onSelect(null);
				} else {
					var files = file.split(";");
					if (options.isAbsolute != true) {
						for (i => file in files) {
							files[i] = makeRelative(file);
						}
					}
					onSelect(files);
				}
			});

			filePickerElement.click();
		}

		if (options.allowNull) {
			haxe.Timer.delay(callback, 100);
		}
		else {
			callback();
		}
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
										var hits : Array<{sheet: cdb.Sheet, path: hide.comp.cdb.Editor.Path}> = [];
										for( rootSheet in database.sheets ) {
											// Don't search through datafiles since we already searched them before with prefabs
											if (rootSheet.props.dataFiles != null && rootSheet.lines == null)
												continue;

											function rec(sheet : cdb.Sheet, objs : Array<Dynamic>, path : hide.comp.cdb.Editor.Path, depth : Int) {
												for (idx => obj in objs) {
													for (c in sheet.columns) {
														if (Reflect.field(obj, c.name) == text) {
															var newPath = new hide.comp.cdb.Editor.Path();
															for (p in path)
																newPath.push(p);
															newPath.push(hide.comp.cdb.Editor.PathPart.Prop(c.name));
															hits.push({ sheet: rootSheet, path: newPath });
														}

														var sub = sheet.getSub(c);
														var subObjs: Array<Dynamic> = c.type.match(cdb.Data.ColumnType.TProperties) ? [Reflect.field(obj, c.name)] : Reflect.field(obj, c.name);
														if (sub != null && subObjs != null) {
															var newPath = new hide.comp.cdb.Editor.Path();
															for (p in path)
																newPath.push(p);
															newPath.push(hide.comp.cdb.Editor.PathPart.Line(idx, c.name));
															rec(sub, subObjs, newPath, depth+1);
														}
													}
												}
											}

											var path = new hide.comp.cdb.Editor.Path();
											rec(rootSheet, rootSheet.lines, path, 0);
										}


										hide.comp.cdb.Editor.openReference2(hits[idx].sheet, hits[idx].path);

									default:
										Ide.showFileInExplorer(absPath + "/" + f);
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

		var adaptedFilter = function(obj: String) {
			return context.filter(obj);
		}

		function filterContent(content:Dynamic) {
			var visited = new Map<Dynamic, Bool>();
			function browseRec(obj:Dynamic) : Dynamic {
				switch( Type.typeof(obj) ) {
				case TObject:
					if( visited.exists(obj)) return null;
					visited.set(obj, true);
					for( f in Reflect.fields(obj) ) {
						var v : Dynamic = Reflect.field(obj, f);
						v = browseRec(v);
						if( v != null ) Reflect.setField(obj, f, v);
					}
				case TClass(Array):
					if( visited.exists(obj)) return null;
					visited.set(obj, true);
					var arr : Array<Dynamic> = obj;
					for( i in 0...arr.length ) {
						var v : Dynamic = arr[i];
						v = browseRec(v);
						if( v != null ) arr[i] = v;
					}
				case TClass(String):
					return context.filter(obj);
				default:
				}
				return null;
			}
			for( f in Reflect.fields(content) ) {
				if (f == "children")
					continue;
				var v = browseRec(Reflect.field(content,f));
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
				p.source = context.filter(p.source);
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
				return {str: p, goto : Ide.showFileInExplorer.bind(getPath(p))};
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
						var v : Dynamic = context.filter(path);
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
							var v : Dynamic = context.filter(tilePos.file);
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
		var font = ideConfig.useAlternateFont ? "Verdana" : "Inter";
		var size = ideConfig.useAlternateFont ? "9pt" : "9.5pt";
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
		var exts = ["props", "json"];
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
		var title = config.current.get("hide.windowTitle");
		window.title = title != null ? title : ((isCDB ? "CastleDB" : "HIDE") + " - " + projectDir);
	}

	public function runCommand(cmd, ?callb:String->Void) {
		var c = cmd.split("%PROJECTDIR%").join(projectDir);
		var slash = isWindows ? "\\" : "/";
		c = c.split("/").join(slash);
		js.node.ChildProcess.exec(c, function(e:js.node.ChildProcess.ChildProcessExecError,_,_) callb(e == null ? null : e.message));
	}

	public function addCustomMenu(item: nw.MenuItem) {
		customMenus.push(item);
	}

	public function initMenu() {

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
					projectConfig.renderer = name;
					config.user.save();
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
			open("hide.view.CdbTable",{});
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

		var proofing = projectConfig.dbProofread == true;
		db.find(".dbProofread").prop("checked", proofing).click(function(_) {
			projectConfig.dbProofread = !proofing;
			config.global.save();
			for( v in getViews(hide.view.CdbTable) )
				v.applyProofing();
			initMenu();
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
		db.find(".dbFormulasEnable").prop("checked",ideConfig.enableDBFormulas).click(function(_) {
			ideConfig.enableDBFormulas = !ideConfig.enableDBFormulas;
			config.global.save();
			hide.comp.cdb.Editor.refreshAll();
		});
		db.find(".dbFormulas").click(function(_) {
			open("hide.comp.cdb.FormulasView",{ path : config.current.get("cdb.formulasFile") });
		});

		// Categories
		{
			function applyCategories() {
				for( v in getViews(hide.view.CdbTable) )
					v.applyCategories(projectConfig.dbCategories);
				initMenu();
			}
			var allCats = hide.comp.cdb.Editor.getCategories(database);
			var showAll = db.find(".dbCatShowAll");
			for(cat in allCats) {
				var isShown = projectConfig.dbCategories == null || projectConfig.dbCategories.indexOf(cat) >= 0;
				new Element("<menu type='checkbox'>").attr("label",cat).prop("checked", isShown).insertBefore(showAll).click(function(_){
					if(projectConfig.dbCategories == null)
						projectConfig.dbCategories = allCats; // Init with all cats
					if(isShown)
						projectConfig.dbCategories.remove(cat);
					else
						projectConfig.dbCategories.push(cat);
					config.user.save();
					applyCategories();
				});
			}
			new Element("<separator>").insertBefore(showAll);

			db.find(".dbCatShowAll").click(function(_) {
				projectConfig.dbCategories = null;
				config.user.save();
				applyCategories();
			});
			db.find(".dbCatHideAll").click(function(_) {
				projectConfig.dbCategories = [];
				config.user.save();
				applyCategories();
			});
		}

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

	public static function showFileInExplorer(path : String) {
		if(!haxe.io.Path.isAbsolute(path)) {
			path = Ide.inst.getPath(path);
		}

		switch(Sys.systemName()) {
			case "Windows": {
				var cmd = "explorer.exe /select," + '"' + StringTools.replace(path, "/", "\\") + '"';
				trace("OpenInExplorer: " + cmd);
				Sys.command(cmd);
			};
			case "Mac":	Sys.command("open " + haxe.io.Path.directory(path));
			default: throw "Exploration not implemented on this platform";
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

	public function globalMessage(element: Element, timeoutSeconds : Float = 5.0) {
		var body = new Element('body');
		var messages = body.find("#message-container");
		if (messages.length == 0) {
			messages = new Element('<div id="message-container"></div>');
			body.append(messages);
		}

		messages.append(element);
		// envie de prendre le raccourci vers le rez de chaussée la

		haxe.Timer.delay(() -> {
			element.addClass("show");
		}, 10);

		if (timeoutSeconds > 0.0) {
			haxe.Timer.delay(() -> {
				element.get(0).ontransitionend = function(_){
					element.remove();
				};
				element.removeClass("show");

			}, Std.int(timeoutSeconds * 1000.0));
		}
	}

	public function quickMessage( text : String, timeoutSeconds : Float = 5.0 ) {
		var str = StringTools.htmlEscape(text);
		str = StringTools.replace(str, "\n", "<br/>");
		var e = new Element('
		<div class="message">
			<div class="icon ico ico-info-circle"></div>
			<div class="text">${str}</div>
		</div>');

		js.Browser.console.log(text);

		globalMessage(e, timeoutSeconds);
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

@:allow(hide.Ide)
class FilterPathContext {
	public var valueCurrent: String;
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

	public function filter(valueCurrent: String) {
		this.valueCurrent = valueCurrent;
		valueChanged = null;
		filterFn(this);
		return changed ? valueChanged : valueCurrent;
	}

	public var getRef : () -> {str: String, ?goto: () -> Void};
}
