package hide.ui;

enum DisplayPosition {
	Left;
	Center;
	Right;
	Bottom;
}

typedef ViewOptions = { ?position : DisplayPosition, ?width : Int }

@:keepSub @:allow(hide.Ide)
class View<T> extends hide.comp.Component {

	var container : golden.Container;
	var watches : Array<{ keep : Bool, path : String, callb : Void -> Void }> = [];
	public var fullScreen(get,set) : Bool;
	public var keys(get,null) : Keys;
	public var state(default, null) : T;
	public var undo(default, null) = new hide.ui.UndoHistory();
	public var config(get, null) : Config;
	public var viewClass(get, never) : String;
	public var defaultOptions(get,never) : ViewOptions;

	var contentWidth(get,never) : Int;
	var contentHeight(get,never) : Int;
	var needRebuild : Bool;

	public function new(state:T) {
		super(null,null);
		element = null;
		this.state = state;
		ide = Ide.inst;
		@:privateAccess ide.currentFullScreen = null;
	}

	public function watch( filePath : String, onChange : Void -> Void, ?opts : { ?checkDelete : Bool, ?keepOnRebuild : Bool } ) {
		if( opts == null ) opts = {};
		ide.fileWatcher.register(filePath, onChange, opts.checkDelete);
		var w = { keep : opts.keepOnRebuild, path : filePath, callb : onChange };
		watches.push(w);
		return w;
	}

	public function unwatch(w) {
		if( watches.remove(w) )
			ide.fileWatcher.unregister(w.path, w.callb);
	}

	function get_config() {
		if( config == null )
			config = ide.currentConfig;
		return config;
	}

	function get_keys() {
		if( keys == null ) {
			keys = new Keys(null);
			keys.register("view.fullScreen", function() fullScreen = !fullScreen);
		}
		return keys;
	}

	public function getTitle() {
		return viewClass.split(".").pop();
	}

	public function onBeforeClose() {
		return true;
	}

	function get_viewClass() {
		return Type.getClassName(Type.getClass(this));
	}

	public function setClipboard( v : Dynamic, ?type : String ) {
		nw.Clipboard.get().set(ide.toJSON({ type : type == null ? viewClass : type, value : v }));
	}

	public function hasClipboard( ?type : String ) {
		if( type == null ) type = viewClass;
		var v : Dynamic = try haxe.Json.parse(nw.Clipboard.get().get()) catch( e : Dynamic ) null;
		return v != null && v.type == type;
	}

	public function getClipboard( ?type : String ) : Dynamic {
		if( type == null ) type = viewClass;
		var v : Dynamic = try haxe.Json.parse(nw.Clipboard.get().get()) catch( e : Dynamic ) null;
		return v == null || v.type != type ? null : v.value;
	}

	function syncTitle() {
		container.setTitle(getTitle());
	}

	public function processKeyEvent( e : js.jquery.Event ) {
		var active = js.Browser.document.activeElement;
		if( active != null && (active.nodeName == "INPUT" || active.nodeName == "TEXTAREA") ) {
			e.stopPropagation();
			return true;
		}
		for( el in element.find("[haskeys=true]").add(element).elements() ) {
			if(el.has(active).length == 0 && el[0] != active)
				continue;
			var keys = hide.ui.Keys.get(el);
			if( keys == null ) continue;
			if( keys.processEvent(e,config) )
				return true;
		}
		// global keys
		return keys.processEvent(e,config);
	}

	public function setContainer(cont) {
		this.container = cont;
		@:privateAccess ide.views.push(this);
		syncTitle();
		container.on("resize",function(_) {
			container.getElement().find('*').trigger('resize');
			onResize();
		});
		container.on("destroy",function(e) {
			destroy();
		});
		container.on("show", function(_) {
			// we are dragging the container tab
			if( container.parent.parent.config == null ) return;
			haxe.Timer.delay(onActivate,0);
		});
		container.getElement().keydown(function(e) {
			processKeyEvent(e);
		});

		container.on("tab", function(e) {
			container.tab.onClose = function() {
				return onBeforeClose();
			};
			container.tab.element.contextmenu(function(e) {
				var menu = buildTabMenu();
				if( menu.length > 0 ) new hide.comp.ContextMenu(menu);
				e.preventDefault();
			});
		});

		untyped cont.parent.__view = this;
		element = cont.getElement();
	}

	public final function rebuild() {
		function checkRebuild() {
			if( container == null || !needRebuild ) return;
			if( !isActive() ) {
				haxe.Timer.delay(checkRebuild,200);
				return;
			}
			needRebuild = false;
			onRebuild();
		}
		if( !needRebuild ) {
			needRebuild = true;
			checkRebuild();
		}
	}

	function onRebuild() {
		for( w in watches.copy() )
			if( !w.keep ) {
				ide.fileWatcher.unregister(w.path, w.callb);
				watches.remove(w);
			}
		syncTitle();
		element.empty();
		element.off();
		onDisplay();
	}

	function onDisplay() {
		element.text(viewClass+(state == null ? "" : " "+state));
	}

	public function onResize() {
	}

	public function onActivate() {
	}

	public function isActive() {
		return container != null && !container.isHidden;
	}

	public function onDragDrop(items : Array<String>, isDrop : Bool) {
		return false;
	}

	function toString() {
		return Type.getClassName(Type.getClass(this)) + (this.state == null ? "" : "("+haxe.Json.stringify(this.state)+")");
	}

	/**
		Gives focus if part of a tab group
	**/
	public function activate() {
		if( container != null ) {
			var cur = container.parent.parent.getActiveContentItem();
			if( cur != container.parent )
				container.parent.parent.setActiveContentItem(container.parent);
		}
	}

	function saveState() {
		container.setState(state);
	}

	public function close() {
		if( container != null )
			container.close();
	}

	function destroy() {
		for( w in watches.copy() )
			ide.fileWatcher.unregister(w.path, w.callb);
		watches = [];
		@:privateAccess ide.views.remove(this);
		for( c in container.getElement().find("canvas") ) {
			var s : hide.comp.Scene = Reflect.field(c, "__scene");
			if( s != null )
				s.dispose();
		}
		element = null;
	}

	function buildTabMenu() : Array<hide.comp.ContextMenu.ContextMenuItem> {
		if( @:privateAccess ide.subView != null )
			return [];
		return [
			{ label : "Close", click : close },
			{ label : "Close Others", click : function() for( v in @:privateAccess ide.views.copy() ) if( v != this && v.container.tab.header == container.tab.header ) v.close() },
			{ label : "Close All", click : function() for( v in @:privateAccess ide.views.copy() ) if( v.container.tab.header == container.tab.header ) v.close() },
		];
	}

	function get_contentWidth() return container.width;
	function get_contentHeight() return container.height;
	function get_defaultOptions() return viewClasses.get(Type.getClassName(Type.getClass(this))).options;

	function get_fullScreen() return container != null && container.getElement().is(".fullScreen");
	function set_fullScreen(v) {
		if( fullScreen == v )
			return v;
		if( container != null ) {
			new Element(".fullScreen").removeClass("fullScreen");
			container.getElement().toggleClass("fullScreen", v);
			new Element("body").toggleClass("fullScreenMode",v);
		}
		@:privateAccess if( v ) ide.currentFullScreen = this else ide.currentFullScreen = null;
		if( !ide.isCDB ) ide.setFullscreen(v);
		return v;
	}

	public static var viewClasses = new Map<String,{ name : String, cl : Class<View<Dynamic>>, options : ViewOptions }>();
	public static function register<T>( cl : Class<View<T>>, ?options : ViewOptions ) {
		var name = Type.getClassName(cl);
		if( viewClasses.exists(name) )
			return null;
		if( options == null )
			options = {}
		if( options.position == null )
			options.position = Center;
		viewClasses.set(name, { name : name, cl : cl, options : options });
		return null;
	}

}