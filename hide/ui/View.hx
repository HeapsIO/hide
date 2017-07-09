package hide.ui;

enum DisplayPosition {
	Left;
	Center;
	Right;
	Bottom;
}

typedef ViewOptions = { ?position : DisplayPosition, ?width : Int }

@:keepSub @:allow(hide.ui.Ide)
class View<T> {

	var ide : Ide;
	var container : golden.Container;
	var state : T;
	public var defaultOptions(get,never) : ViewOptions;

	var contentWidth(get,never) : Int;
	var contentHeight(get,never) : Int;

	public function new(state:T) {
		this.state = state;
		ide = Ide.inst;
	}

	public function getTitle() {
		var name = Type.getClassName(Type.getClass(this));
		return name.split(".").pop();
	}

	public function onBeforeClose() {
		return true;
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
		});
		untyped cont.parent.__view = this;
	}

	public function rebuild() {
		if( container == null ) return;
		syncTitle();
		var e = container.getElement();
		e.html('');
		onDisplay(container.getElement());
	}

	public function onDisplay( e : Element ) {
		e.text(Type.getClassName(Type.getClass(this))+(state == null ? "" : " "+state));
	}

	public function onResize() {
	}

	public function saveState() {
		container.setState(state);
	}

	public function close() {
		if( container != null ) {
			container.close();
			container = null;
		}
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