package hide.ui;

class Ide {

	public var props : Props;
	public var projectDir(get,never) : String;
	public var resourceDir(get,never) : String;
	public var initializing(default,null) : Bool;

	public var mouseX : Int = 0;
	public var mouseY : Int = 0;

	var window : nw.Window;

	var layout : golden.Layout;
	var types : Map<String,hide.HType>;
	var typeDef = Macros.makeTypeDef(hide.HType);

	var menu : Element;
	var currentLayout : { name : String, state : Dynamic };
	var maximized : Bool;
	var updates : Array<Void->Void> = [];
	var views : Array<View<Dynamic>> = [];

	function new() {
		inst = this;
		window = nw.Window.get();
		props = new Props(Sys.getCwd());

		var wp = props.global.windowPos;
		if( wp != null ) {
			window.resizeBy(wp.w - Std.int(window.window.outerWidth), wp.h - Std.int(window.window.outerHeight));
			window.moveTo(wp.x, wp.y);
			if( wp.max ) window.maximize();
		}
		window.show(true);

		setProject(props.global.currentProject);
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

		var body = window.window.document.body;
		body.onfocus = function(_) haxe.Timer.delay(function() new Element(body).find("input[type=file]").change().remove(), 200);
	}

	function onWindowChange() {
		if( props.global.windowPos == null ) props.global.windowPos = { x : 0, y : 0, w : 0, h : 0, max : false };
		props.global.windowPos.max = maximized;
		if( !maximized ) {
			props.global.windowPos.x = window.x;
			props.global.windowPos.y = window.y;
			props.global.windowPos.w = Std.int(window.window.outerWidth);
			props.global.windowPos.h = Std.int(window.window.outerHeight);
		}
		props.saveGlobals();
	}

	function initLayout( ?state : { name : String, state : Dynamic } ) {

		initializing = true;

		if( layout != null ) {
			layout.destroy();
			layout = null;
		}

		var defaultLayout = null;
		for( p in props.current.layouts )
			if( p.name == "Default" ) {
				defaultLayout = p;
				break;
			}
		if( defaultLayout == null ) {
			defaultLayout = { name : "Default", state : [] };
			if( props.local.layouts == null ) props.local.layouts = [];
			props.local.layouts.push(defaultLayout);
			props.save();
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
				try view.onDisplay(cont.getElement()) catch( e : Dynamic ) js.Browser.alert(vcl.name+":"+e);
			});

		layout.init();
		layout.on('stateChanged', function() {
			if( !props.current.autoSaveLayout )
				return;
			defaultLayout.state = saveLayout();
			props.save();
		});

		// error recovery if invalid component
		haxe.Timer.delay(function() {
			initializing = false;
			if( layout.isInitialised ) return;
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

	public function getPath( relPath : String ) {
		if( haxe.io.Path.isAbsolute(relPath) )
			return relPath;
		return resourceDir+"/"+relPath;
	}

	function get_projectDir() return props.global.currentProject.split("\\").join("/");
	function get_resourceDir() return projectDir+"/res";

	function setProject( dir : String ) {
		if( dir != props.global.currentProject ) {
			props.global.currentProject = dir;
			if( props.global.recentProjects == null ) props.global.recentProjects = [];
			props.global.recentProjects.remove(dir);
			props.global.recentProjects.unshift(dir);
			if( props.global.recentProjects.length > 10 ) props.global.recentProjects.pop();
			props.save();
		}
		window.title = "HIDE - " + dir;
		props = new Props(dir);
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
		var e = new Element('<input type="file" value="" accept="${[for( e in exts ) "."+e].join(",")}"/>');
		e.change(function(_) {
			var file = makeRelative(e.val());
			e.remove();
			onSelect(file == "" ? null : file);
		}).appendTo(window.window.document.body).click();
	}

	public function chooseDirectory( onSelect : String -> Void ) {
		var e = new Element('<input type="file" value="" nwdirectory/>');
		e.change(function(_) {
			var dir = makeRelative(js.jquery.Helper.JTHIS.val());
			onSelect(dir == "" ? null : dir);
			e.remove();
		}).appendTo(window.window.document.body).click();
	}

	function initMenu() {
		if( menu == null )
			menu = new Element(new Element("#mainmenu").get(0).outerHTML);

		// project
		if( props.current.recentProjects.length > 0 )
			menu.find(".project .recents").html("");
		for( v in props.current.recentProjects.copy() ) {
			if( !sys.FileSystem.exists(v) ) {
				props.current.recentProjects.remove(v);
				props.save();
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
			props.global.recentProjects = [];
			props.save();
			initMenu();
		});
		menu.find(".project .exit").click(function(_) {
			Sys.exit(0);
		});

		// view
		menu.find(".debug").click(function(_) window.showDevTools());
		var comps = menu.find("[component]");
		for( c in comps.elements() ) {
			var cname = c.attr("component");
			var cl = Type.resolveClass(cname);
			if( cl == null ) js.Browser.alert("Missing component class "+cname);
			var state = c.attr("state");
			if( state != null ) try haxe.Json.parse(state) catch( e : Dynamic ) js.Browser.alert("Invalid state "+state+" ("+e+")");
			c.click(function(_) {
				open(cname, state == null ? null : haxe.Json.parse(state));
			});
		}

		// layout
		var layouts = menu.find(".layout .content");
		layouts.html("");
		for( l in props.current.layouts ) {
			if( l.name == "Default" ) continue;
			new Element("<menu>").attr("label",l.name).addClass(l.name).appendTo(layouts).click(function(_) {
				initLayout(l);
			});
		}
		menu.find(".layout .autosave").click(function(_) {
			props.local.autoSaveLayout = !props.local.autoSaveLayout;
			props.save();
		}).attr("checked",props.local.autoSaveLayout?"checked":"");

		menu.find(".layout .saveas").click(function(_) {
			var name = js.Browser.window.prompt("Please enter a layout name:");
			if( name == null || name == "" ) return;
			props.local.layouts.push({ name : name, state : saveLayout() });
			props.save();
			initMenu();
		});
		menu.find(".layout .save").click(function(_) {
			currentLayout.state = saveLayout();
			props.save();
		});

		window.menu = new Menu(menu).root;
	}

	public function open( component : String, state : Dynamic, ?onCreate : View<Dynamic> -> Void ) {
		var options = View.viewClasses.get(component).options;

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

	public static var inst : Ide;

	static function main() {
		new Ide();
	}

}
