package hide.ui;

enum DisplayPosition {
	Left;
	Center;
	Right;
	Bottom;
}

typedef ViewOptions = { ?position : DisplayPosition, ?width : Int }

@:keepSub @:allow(hide.ui.Ide)
class View<T> extends hide.comp.Component {

	var container : golden.Container;
	var state : T;
	var keys(get,null) : Keys;
	var props(get,null) : Props;
	var undo = new hide.ui.UndoHistory();
	public var viewClass(get, never) : String;
	public var defaultOptions(get,never) : ViewOptions;

	var contentWidth(get,never) : Int;
	var contentHeight(get,never) : Int;

	public function new(state:T) {
		super(null);
		this.state = state;
		ide = Ide.inst;
	}

	function get_props() {
		if( props == null )
			props = ide.currentProps;
		return props;
	}

	function get_keys() {
		if( keys == null ) keys = new Keys(props);
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

	public function setContainer(cont) {
		this.container = cont;
		@:privateAccess ide.views.push(this);
		syncTitle();
		container.on("resize",function(_) {
			container.getElement().find('*').trigger('resize');
			onResize();
		});
		container.on("destroy",function(e) {
			if( !onBeforeClose() ) {
				e.preventDefault();
				return;
			}
			@:privateAccess ide.views.remove(this);
			for( c in container.getElement().find("canvas") ) {
				var s : hide.comp.Scene = Reflect.field(c, "__scene");
				if( s != null )
					s.dispose();
			}
		});
		container.getElement().keydown(function(e) {
			keys.processEvent(e);
		});

		container.on("tab", function(e) {
			container.tab.element.contextmenu(function(e) {
				new hide.comp.ContextMenu(buildTabMenu());
				e.preventDefault();
			});
		});

		untyped cont.parent.__view = this;
		root = cont.getElement();
	}

	public function rebuild() {
		if( container == null ) return;
		syncTitle();
		root.html('');
		onDisplay();
	}

	public function onDisplay() {
		root.text(viewClass+(state == null ? "" : " "+state));
	}

	public function onResize() {
	}

	public function saveState() {
		container.setState(state);
	}

	public function close() {
		if( container != null )
			container.close();
	}

	function buildTabMenu() : Array<hide.comp.ContextMenu.ContextMenuItem> {
		return [
			{ label : "Close", click : close },
			{ label : "Close Others", click : function() for( v in @:privateAccess ide.views ) if( v != this && v.container.tab.header == container.tab.header ) v.close() },
			{ label : "Close All", click : function() for( v in @:privateAccess ide.views ) if( v.container.tab.header == container.tab.header ) v.close() },
		];
	}

	function get_contentWidth() return container.width;
	function get_contentHeight() return container.height;
	function get_defaultOptions() return viewClasses.get(Type.getClassName(Type.getClass(this))).options;

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