package hide.ui;

class Ide {

	public var currentProps(get,never) : Props;
	public var projectDir(get,never) : String;
	public var resourceDir(get,never) : String;
	public var initializing(default,null) : Bool;

	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	public var isWindows(get, never) : Bool;

	public var database : cdb.Database;
	public var shaderLoader : hide.tools.ShaderLoader;
	public var fileWatcher : hide.tools.FileWatcher;

	var databaseFile : String;

	var props : {
		global : Props,
		project : Props,
		user : Props,
		current : Props,
	};
	var ideProps(get, never) : Props.HideProps;

	var window : nw.Window;
	var layout : golden.Layout;

	var currentLayout : { name : String, state : Dynamic };
	var maximized : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<View<Dynamic>> = [];

	var renderers : Array<h3d.mat.MaterialSetup>;

	function new() {
		inst = this;
		window = nw.Window.get();
		var cwd = Sys.getCwd();
		props = Props.loadForProject(cwd, cwd+"/res");

		var wp = props.global.current.hide.windowPos;
		if( wp != null ) {
			if( wp.w > 400 && wp.h > 300 )
				window.resizeBy(wp.w - Std.int(window.window.outerWidth), wp.h - Std.int(window.window.outerHeight));
			if( wp.x >= 0 && wp.y >= 0 ) {
				window.moveTo(wp.x, wp.y);
				if( wp.max ) window.maximize();
			}
		}
		window.show(true);

		fileWatcher = new hide.tools.FileWatcher();

		setProject(ideProps.currentProject);
		window.window.document.addEventListener("mousemove", function(e) {
			mouseX = e.x;
			mouseY = e.y;
		});
		window.on('maximize', function() { maximized = true; onWindowChange(); });
		window.on('restore', function() { maximized = false; onWindowChange(); });
		window.on('move', function() haxe.Timer.delay(onWindowChange,100));
		window.on('resize', function() haxe.Timer.delay(onWindowChange,100));
		window.on('close', function() {
			for( v in views )
				if( !v.onBeforeClose() )
					return;
			window.close(true);
		});

		// handle commandline parameters
		nw.App.on("open", function(cmd) {
			~/"([^"]+)"/g.map(cmd, function(r) {
				var file = r.matched(1);
				if( sys.FileSystem.exists(file) ) openFile(file);
				return "";
			});
		});

		// handle cancel on type=file
		var body = window.window.document.body;
		body.onfocus = function(_) haxe.Timer.delay(function() new Element(body).find("input[type=file]").change().remove(), 200);

		// dispatch global keys based on mouse position
		new Element(body).keydown(function(e) {
			for( v in views ) {
				var c = v.root.offset();
				if( mouseX >= c.left && mouseY >= c.top && mouseX <= c.left + v.root.outerWidth() && mouseY <= c.top + v.root.outerHeight() ) {
					v.keys.processEvent(e);
					break;
				}
			}
		});
	}

	function get_isWindows() {
		return true;
	}

	function onWindowChange() {
		if( ideProps.windowPos == null ) ideProps.windowPos = { x : 0, y : 0, w : 0, h : 0, max : false };
		ideProps.windowPos.max = maximized;
		if( !maximized ) {
			ideProps.windowPos.x = window.x;
			ideProps.windowPos.y = window.y;
			ideProps.windowPos.w = Std.int(window.window.outerWidth);
			ideProps.windowPos.h = Std.int(window.window.outerHeight);
		}
		props.global.save();
	}

	function initLayout( ?state : { name : String, state : Dynamic } ) {

		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		var defaultLayout = null;
		for( p in props.current.current.hide.layouts )
			if( p.name == "Default" ) {
				defaultLayout = p;
				break;
			}
		if( defaultLayout == null ) {
			defaultLayout = { name : "Default", state : [] };
			ideProps.layouts.push(defaultLayout);
			props.current.sync();
			props.global.save();
		}
		if( state == null )
			state = defaultLayout;

		this.currentLayout = state;

		var config : golden.Config = {
			content: state.state,
		};
		var comps = new Map();
		for( vcl in View.viewClasses )
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

		for( vcl in View.viewClasses )
			layout.registerComponent(vcl.name,function(cont,state) {
				var view = Type.createInstance(vcl.cl,[state]);
				view.setContainer(cont);
				try view.onDisplay() catch( e : Dynamic ) error(vcl.name+":"+e);
			});

		layout.init();
		layout.on('stateChanged', function() {
			if( !ideProps.autoSaveLayout )
				return;
			defaultLayout.state = saveLayout();
			props.global.save();
		});

		// error recovery if invalid component
		haxe.Timer.delay(function() {
			initializing = false;
			if( layout.isInitialised ) {
				for( file in nw.App.argv ) {
						if( !sys.FileSystem.exists(file) ) continue;
						openFile(file);
					}
				return;
			}
			state.state = [];
			initLayout();
		}, 1000);

		hxd.System.setLoop(mainLoop);
	}

	function mainLoop() {
		for( f in updates )
			f();
	}

	function saveLayout() {
		return layout.toConfig().content;
	}

	function get_ideProps() return props.global.source.hide;
	function get_currentProps() return props.user;

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
		if( haxe.io.Path.isAbsolute(relPath) )
			return relPath;
		return resourceDir+"/"+relPath;
	}

	public function error( e : Dynamic ) {
		js.Browser.alert(e);
	}

	function get_projectDir() return ideProps.currentProject.split("\\").join("/");
	function get_resourceDir() return projectDir+"/res";

	function setProject( dir : String ) {
		if( dir != ideProps.currentProject ) {
			ideProps.currentProject = dir;
			ideProps.recentProjects.remove(dir);
			ideProps.recentProjects.unshift(dir);
			if( ideProps.recentProjects.length > 10 ) ideProps.recentProjects.pop();
			props.global.save();
		}
		window.title = "HIDE - " + dir;
		props = Props.loadForProject(projectDir, resourceDir);
		shaderLoader = new hide.tools.ShaderLoader();

		var localDir = sys.FileSystem.exists(resourceDir) ? resourceDir : projectDir;
		hxd.res.Loader.currentInstance = new CustomLoader(new hxd.fs.LocalFileSystem(localDir));
		renderers = [
			new h3d.mat.MaterialSetup("Default"),
		];
		var path = getPath("Renderer.hx");
		if( sys.FileSystem.exists(path) ) {
			var r = new hide.tools.MaterialScript();
			try {
				r.load(sys.io.File.getContent(path));
				renderers.unshift(r);
			} catch( e : Dynamic ) {
				error(e);
			}
			r.onError = function(msg) error(msg);
		}

		var db = getPath("data.cdb");
		databaseFile = db;
		database = new cdb.Database();
		if( sys.FileSystem.exists(db) ) {
			try {
				database.load(sys.io.File.getContent(db));
			} catch( e : Dynamic ) {
				error(e);
			}
		}

		var render = renderers[0];
		for( r in renderers )
			if( r.name == props.current.current.hide.renderer ) {
				render = r;
				break;
			}
		h3d.mat.MaterialSetup.current = render;

		initMenu();
		initLayout();
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

	function initMenu() {
		var menu = new Element(new Element("#mainmenu").get(0).outerHTML);

		// project
		if( ideProps.recentProjects.length > 0 )
			menu.find(".project .recents").html("");
		for( v in ideProps.recentProjects.copy() ) {
			if( !sys.FileSystem.exists(v) ) {
				ideProps.recentProjects.remove(v);
				props.global.save();
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
			ideProps.recentProjects = [];
			props.global.save();
			initMenu();
		});
		menu.find(".project .exit").click(function(_) {
			Sys.exit(0);
		});

		for( r in renderers ) {
			new Element("<menu type='checkbox'>").attr("label", r.name).prop("checked",r == h3d.mat.MaterialSetup.current).appendTo(menu.find(".project .renderers")).click(function(_) {
				if( r != h3d.mat.MaterialSetup.current ) {
					if( props.user.source.hide == null ) props.user.source.hide = cast {};
					props.user.source.hide.renderer = r.name;
					props.user.save();
					setProject(ideProps.currentProject);
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
		for( l in props.current.current.hide.layouts ) {
			if( l.name == "Default" ) continue;
			new Element("<menu>").attr("label",l.name).addClass(l.name).appendTo(layouts).click(function(_) {
				initLayout(l);
			});
		}
		menu.find(".layout .autosave").click(function(_) {
			ideProps.autoSaveLayout = !ideProps.autoSaveLayout;
			props.global.save();
		}).prop("checked",ideProps.autoSaveLayout);

		menu.find(".layout .saveas").click(function(_) {
			var name = ask("Please enter a layout name:");
			if( name == null || name == "" ) return;
			ideProps.layouts.push({ name : name, state : saveLayout() });
			props.global.save();
			initMenu();
		});
		menu.find(".layout .save").click(function(_) {
			currentLayout.state = saveLayout();
			props.global.save();
		});

		window.menu = new Menu(menu).root;
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

	public function open( component : String, state : Dynamic, ?onCreate : View<Dynamic> -> Void ) {
		var c = View.viewClasses.get(component);

		if( c == null )
			throw "Unknown component " + component;

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

	public function confirm( text : String ) {
		return js.Browser.window.confirm(text);
	}

	public function ask( text : String, ?defaultValue = "" ) {
		return js.Browser.window.prompt(text, defaultValue);
	}

	public static var inst : Ide;

	static function main() {
		h3d.pass.ShaderManager.STRICT = false; // prevent errors with bad renderer
		hide.tools.Macros.include(["hide.view","h3d.prim","h3d.scene","h3d.pass","hide.prefab"]);
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
