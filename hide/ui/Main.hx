package hide.ui;
import js.jquery.Helper.*;

class Main {

	var window : nw.Window;

	var layout : golden.Layout;
	var types : Map<String,hide.HType>;
	var typeDef = Macros.makeTypeDef(hide.HType);

	var props : Props;
	var menu : js.jquery.JQuery;
	var currentLayout : { name : String, state : Dynamic };

	function new() {
		props = new Props();
		props.load();
		window = nw.Window.get();
		initMenu();
		initLayout();
	}

	function initLayout( ?state : { name : String, state : Dynamic } ) {

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
		layout = new golden.Layout(config);

		for( cl in @:privateAccess View.viewClasses )
			layout.registerComponent(Type.getClassName(cl),function(cont,state) {
				var view = Type.createInstance(cl,[state]);
				cont.setTitle(view.getTitle());
				view.onDisplay(cont.getElement());
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
			if( layout.isInitialised ) return;
			state.state = [];
			initLayout();
		}, 1000);
	}

	function saveLayout() {
		return layout.toConfig().content;
	}

	function initMenu() {
		var firstInit = false;

		if( menu == null ) {
			menu = J("#mainmenu");
			firstInit = true;
		}

		// states

		var layouts = menu.find(".layout .content");
		layouts.html("");
		for( l in props.current.layouts ) {
			if( l.name == "Default" ) continue;
			J("<menu>").attr("label",l.name).addClass(l.name).appendTo(layouts).click(function(_) {
				initLayout(l);
			});
		}
		if( firstInit ) {
			menu.find(".layout .autosave").click(function(_) {
				props.local.autoSaveLayout = !props.local.autoSaveLayout;
				props.save();
			});
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
		}
		menu.find(".layout .autosave").attr("checked",props.local.autoSaveLayout?"checked":"");

		// view
		if( firstInit ) {
			menu.find(".debug").click(function(_) window.showDevTools());
			var comps = menu.find("[component]");
			for( c in comps.elements() ) {
				var cname = c.attr("component");
				var cl = Type.resolveClass(cname);
				if( cl == null ) js.Browser.alert("Missing component class "+cname);
				c.click(function(_) {
					if( layout.root.contentItems.length == 0 )
						layout.root.addChild({ type : Row });
					layout.root.contentItems[0].addChild({
						type : Component,
						componentName : cname,
					});
				});
			}
		}
		window.menu = new Menu(menu).root;
	}


	static function main() {
		new Main();
	}

}
