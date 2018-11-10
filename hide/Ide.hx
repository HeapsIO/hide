package hide;
import hxd.inspect.Group;

@:expose
class Ide {

	public var currentConfig(get,never) : Config;
	public var projectDir(get,never) : String;
	public var resourceDir(get,never) : String;
	public var initializing(default,null) : Bool;
	public var appPath(get, never): String;

	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	public var isWindows(get, never) : Bool;

	public var database : cdb.Database;
	public var databaseApi : hide.comp.cdb.Editor.EditorApi;
	public var shaderLoader : hide.tools.ShaderLoader;
	public var fileWatcher : hide.tools.FileWatcher;
	public var typesCache : hide.tools.TypesCache;

	var databaseFile : String;

	var config : {
		global : Config,
		project : Config,
		user : Config,
		current : Config,
	};
	var ideConfig(get, never) : hide.Config.HideConfig;

	var window : nw.Window;
	var layout : golden.Layout;

	var currentLayout : { name : String, state : Dynamic };
	var maximized : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<hide.ui.View<Dynamic>> = [];

	var renderers : Array<h3d.mat.MaterialSetup>;
	var subView : { component : String, state : Dynamic, events : {} };
	var scripts : Map<String,Array<Void->Void>> = new Map();
	var hasReloaded = false;

	static var firstInit = true;

	function new() {
		inst = this;
		window = nw.Window.get();
		var cwd = Sys.getCwd();
		config = Config.loadForProject(cwd, cwd+"/res");

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
			var wp = config.global.current.hide.windowPos;
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

		setProject(ideConfig.currentProject);
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
			for( v in views )
				if( !v.onBeforeClose() )
					return;
			window.close(true);
		});
		window.on('blur', function() if( h3d.Engine.getCurrent() != null && !hasReloaded ) hxd.Key.initialize());

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
		new Element(window.window.document).on("dnd_stop.vakata.jstree", function(e, data) {
			var nodeIds : Array<String> = cast data.data.nodes;
			if(data.data.jstree == null) return;
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
				if(view != null) {
					view.onDragDrop(paths, true);
					return;
				}
			}
		});

		// dispatch global keys based on mouse position
		new Element(body).keydown(function(e) {
			var view = getViewAt(mouseX, mouseY);
			if(view != null) view.processKeyEvent(e);
		});
	}

	public function getViews<K,T:hide.ui.View<K>>( cl : Class<T> ) {
		return [for( v in views ) { var t = Std.instance(v,cl); if( t != null ) t; }];
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

	function initLayout( ?state : { name : String, state : Dynamic } ) {

		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		var defaultLayout = null;
		for( p in config.current.current.hide.layouts )
			if( p.name == "Default" ) {
				defaultLayout = p;
				break;
			}
		if( defaultLayout == null ) {
			defaultLayout = { name : "Default", state : [] };
			ideConfig.layouts.push(defaultLayout);
			config.current.sync();
			config.global.save();
		}
		if( state == null )
			state = defaultLayout;

		if( subView != null )
			state = { name : "SubView", state : [] };

		this.currentLayout = state;

		var config : golden.Config = {
			content: state.state,
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

		for( vcl in hide.ui.View.viewClasses )
			layout.registerComponent(vcl.name,function(cont,state) {
				var view = Type.createInstance(vcl.cl,[state]);
				view.setContainer(cont);
				try view.onDisplay() catch( e : Dynamic ) error(vcl.name+":"+e);
			});

		layout.init();
		layout.on('stateChanged', function() {
			if( !ideConfig.autoSaveLayout )
				return;
			defaultLayout.state = saveLayout();
			if( subView == null ) this.config.global.save();
		});

		var waitCount = 0;
		function waitInit() {
			waitCount++;
			if( !layout.isInitialised ) {
				if( waitCount > 20 ) {
					// timeout : error recovery if invalid component
					state.state = [];
					initLayout();
					return;
				}
				haxe.Timer.delay(waitInit, 50);
				return;
			}
			initializing = false;
			if( subView == null && views.length == 0 )
				open("hide.view.FileTree",{path:""});
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
		for( f in updates )
			f();
	}

	function saveLayout() {
		return layout.toConfig().content;
	}

	function get_ideConfig() return config.global.source.hide;
	function get_currentConfig() return config.user;
	function get_appPath() {
		var path = js.Node.process.argv[0].split("\\").join("/").split("/");
		path.pop();
		var hidePath = path.join("/");
		if( !sys.FileSystem.exists(hidePath + "/package.json") ) {
			var prevPath = new haxe.io.Path(hidePath).dir;
			if( sys.FileSystem.exists(prevPath + "/hide.js") )
				return prevPath;
			// nwjs launch
			var path = Sys.getCwd();
			if( sys.FileSystem.exists(path+"/hide.js") )
				return path;
			message("Hide application path was not found");
			Sys.exit(0);
		}
		return hidePath;
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
		if( dir != ideConfig.currentProject ) {
			ideConfig.currentProject = dir;
			ideConfig.recentProjects.remove(dir);
			ideConfig.recentProjects.unshift(dir);
			if( ideConfig.recentProjects.length > 10 ) ideConfig.recentProjects.pop();
			config.global.save();
		}
		window.title = "HIDE - " + dir;
		config = Config.loadForProject(projectDir, resourceDir);
		shaderLoader = new hide.tools.ShaderLoader();
		typesCache = new hide.tools.TypesCache();

		var localDir = sys.FileSystem.exists(resourceDir) ? resourceDir : projectDir;
		hxd.res.Loader.currentInstance = new CustomLoader(new hxd.fs.LocalFileSystem(localDir));
		renderers = [
			new hide.Renderer.MaterialSetup("Default"),
			new hide.Renderer.PbrSetup("PBR"),
		];

		var plugins : Array<String> = config.current.get("plugins");
		for( file in plugins )
			loadScript(file, function() {});

		var db = getPath(config.project.get("cdb.databaseFile"));
		databaseFile = db;
		database = new cdb.Database();
		if( sys.FileSystem.exists(db) ) {
			try {
				database.load(sys.io.File.getContent(db));
			} catch( e : Dynamic ) {
				error(e);
			}
		}
		databaseApi = {
			copy : () -> (database.save() : Any),
			load : (v:Any) -> database.load((v:String)),
			save : saveDatabase,
			undo : new hide.ui.UndoHistory(),
			undoState : [], // common
		};
		databaseApi.editor = new hide.comp.cdb.AllEditors();

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
			for( r in renderers )
				if( r.name == config.current.current.hide.renderer ) {
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

	function loadScript( file : String, callb : Void -> Void ) {
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
		var e = js.Browser.document.createScriptElement();
		e.addEventListener("load", function() {
			scripts.set(file, []);
			for( w in wait )
				w();
			if( !isScriptLoading() ) {
				wait = scripts.get("");
				scripts.set("",[]);
				for( w in wait ) w();
			}
		});
		e.addEventListener("error", function(e) {
			error("Error while loading "+file);
		});
		e.async = false;
		e.type = "text/javascript";
		e.src = "file://"+file.split("\\").join("/");
		js.Browser.document.body.appendChild(e);
		fileWatcher.register(file,reload);
	}

	public function reload() {
		hasReloaded = true;
		fileWatcher.dispose();
		js.Browser.location.reload();
	}

	public function saveDatabase() {
		sys.io.File.saveContent(databaseFile, database.save());
	}

	public function makeRelative( path : String ) {
		path = path.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), resourceDir.toLowerCase()+"/") )
			return path.substr(resourceDir.length+1);
		return path;
	}

	public function chooseFile( exts : Array<String>, onSelect : String -> Void ) {
		var e = new Element('<input type="file" style="visibility:hidden" value="" accept="${[for( e in exts ) "."+e].join(",")}"/>');
		e.change(function(_) {
			var file = makeRelative(e.val());
			e.remove();
			onSelect(file == "" ? null : file);
		}).appendTo(window.window.document.body).click();
	}

	public function chooseFileSave( defaultPath : String, onSelect : String -> Void ) {
		var path = getPath(defaultPath).split("/");
		var file = path.pop();
		var c = isWindows ? "\\" : "/";
		var path = path.join(c);
		var e = new Element('<input type="file" style="visibility:hidden" value="" nwworkingdir="$path" nwsaveas="$path$c$file"/>');
		e.change(function(_) {
			var file = makeRelative(e.val());
			e.remove();
			onSelect(file == "" ? null : file);
		}).appendTo(window.window.document.body).click();
	}

	public function chooseDirectory( onSelect : String -> Void ) {
		var e = new Element('<input type="file" style="visibility:hidden" value="" nwdirectory/>');
		e.change(function(ev) {
			var dir = makeRelative(ev.getThis().val());
			onSelect(dir == "" ? null : dir);
			e.remove();
		}).appendTo(window.window.document.body).click();
	}

	public function parseJSON( str : String ) {
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

	public function loadPrefab<T:hide.prefab.Prefab>( file : String, ?cl : Class<T> ) : T {
		if( file == null )
			return null;
		var l = hxd.prefab.Library.create(file.split(".").pop().toLowerCase());
		try {
			l.load(parseJSON(sys.io.File.getContent(getPath(file))));
		} catch( e : Dynamic ) {
			error("Invalid prefab ("+e+")");
			throw e;
		}
		if( cl == null || Std.is(l,cl) )
			return cast l;
		return l.get(cl);
	}

	public function savePrefab( file : String, f : hide.prefab.Prefab ) {
		var content;
		if( Std.is(f,hxd.prefab.Library) )
			content = f.save();
		else {
			var l = new hxd.prefab.Library();
			@:privateAccess l.children.push(f); // hack (don't remove f from current parent)
			content = l.save();
		}
		sys.io.File.saveContent(getPath(file), toJSON(content));
	}

	public function filterPrefabs( callb : hxd.prefab.Prefab -> Bool ) {
		var exts = Lambda.array({iterator : @:privateAccess hxd.prefab.Library.registeredExtensions.keys });
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
			todo.push(function() sys.io.File.saveContent(getPath(path), toJSON(prefab.save())));
		});
		for( t in todo )
			t();
	}

	function browseFiles( callb : String -> Void ) {
		function browseRec(path) {
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

		var menu = new Element(new Element("#mainmenu").get(0).outerHTML);

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

		for( r in renderers ) {
			new Element("<menu type='checkbox'>").attr("label", r.name).prop("checked",r == h3d.mat.MaterialSetup.current).appendTo(menu.find(".project .renderers")).click(function(_) {
				if( r != h3d.mat.MaterialSetup.current ) {
					if( config.user.source.hide == null ) config.user.source.hide = cast {};
					config.user.source.hide.renderer = r.name;
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
		for( s in database.sheets ) {
			if( s.props.hide ) continue;
			new Element("<menu>").attr("label", s.name).appendTo(db.find(".dbview")).click(function(_) {
				open("hide.view.CdbTable", { path : s.name });
			});
		}

		// layout
		var layouts = menu.find(".layout .content");
		layouts.html("");
		for( l in config.current.current.hide.layouts ) {
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
			ideConfig.layouts.push({ name : name, state : saveLayout() });
			config.global.save();
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
		var width : Null<Int> = null;
		var target;
		if( bestTarget != null )
			target = bestTarget.parent.parent;
		else {
			target = layout.root.contentItems[0];
			var reqKind : golden.Config.ItemType = options.position == Bottom ? Column : Row;
			if( target == null ) {
				layout.root.addChild({ type : Row });
				target = layout.root.contentItems[0];
			} else if( target.type != reqKind ) {
				// a bit tricky : change the top 'stack' into a 'row'
				// require closing all and reopening (sadly)
				var config = layout.toConfig().content;
				var items = target.getItemsByFilter(function(r) return r.type == Component);
				var foundViews = [];
				for( v in views.copy() )
					if( items.remove(v.container.parent) ) {
						foundViews.push(v);
						v.container.close();
					}
				layout.root.addChild({ type : reqKind, content : config });
				target = layout.root.contentItems[0];
				if( options.position == Left ) index = 0;
				width = options.width;

				// when opening left/right
				if( width == null && foundViews.length == 1 ) {
					var opt = foundViews[0].defaultOptions.width;
					if( opt != null )
						width = Std.int(target.element.width()) - opt;
				}
			}
		}
		if( onCreate != null )
			target.on("componentCreated", function(c) {
				target.off("componentCreated");
				onCreate(untyped c.origin.__view);
			});
		var config : golden.Config.ItemConfig = {
			type : Component,
			componentName : component,
			componentState : state,
		};

		// not working... see https://github.com/deepstreamIO/golden-layout/issues/311
		if( width != null )
			config.width = Std.int(width * 100 / target.element.width());

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
		hide.tools.Macros.include(["hide.view","h3d.prim","h3d.scene","h3d.pass","hide.prefab","hxd.prefab"]);
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
		if( (c:Dynamic) == (hxd.res.Image:Dynamic) )
			return cast loadImage(path);
		return super.loadCache(path, c);
	}

	function loadImage( path : String ) {
		var engine = h3d.Engine.getCurrent();
		var i : hxd.res.Image = @:privateAccess engine.resCache.get(getKey(path));
		if( i == null ) {
			i = new hxd.res.Image(fs.get(path));
			@:privateAccess engine.resCache.set(getKey(path), i);
		}
		return i;
	}

}
