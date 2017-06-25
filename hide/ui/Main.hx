package hide.ui;

class Main {

	var window : nw.Window;
	var mainMenu : nw.Menu;
	var viewMenu : nw.Menu;

	var layout : golden.Layout;

	function new() {
		var config : golden.Config = {
			content: []
		};
		layout = new golden.Layout(config);
		layout.init();

		window = nw.Window.get();
		mainMenu = new nw.Menu({type: Menubar});
		viewMenu = new nw.Menu({type: ContextMenu});


		viewMenu.append(new nw.MenuItem({label:null, type:Separator}));
		addGlobalView(hide.view.About);

		var view = new nw.MenuItem({label:"View", submenu:viewMenu});

		var debug = new nw.MenuItem({label:"Debug"});
		debug.click = function() window.showDevTools();
		viewMenu.append(debug);

		mainMenu.append(view);
		nw.Window.get().menu = mainMenu;
	}

	function addGlobalView( c : Class<View<Dynamic>> ) {
		var cname = Type.getClassName(c);
		var i = new nw.MenuItem({ label : cname.split(".").pop() });
		i.click = function() {
			if( layout.root.contentItems.length == 0 )
				layout.root.addChild({ type : Row });

			layout.root.contentItems[0].addChild({
				type : Component,
				componentName : cname,
			});
		};
		viewMenu.append(i);
		layout.registerComponent(cname, function(cont, state) {
			var view = Type.createInstance(c, [state]);
			cont.setTitle(view.getTitle());
			view.onDisplay(cont.getElement());
		});
	}

	static function main() {
		new Main();
	}

}
