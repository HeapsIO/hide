package hide.ui;

enum DisplayPosition {
	Left;
	Center;
	Right;
	Bottom;
}

@:keepSub @:allow(hide.ui.Ide)
class View<T> {

	var ide : Ide;
	var container : golden.Container;
	var state : T;
	public var defaultPosition(get,never) : DisplayPosition;

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
	function get_defaultPosition() return viewClasses.get(Type.getClassName(Type.getClass(this))).position;

	public static var viewClasses = new Map<String,{ name : String, cl : Class<View<Dynamic>>, position : DisplayPosition }>();
	public static function register<T>( cl : Class<View<T>>, ?position : DisplayPosition ) {
		var name = Type.getClassName(cl);
		if( viewClasses.exists(name) )
			return null;
		if( position == null )
			position = Center;
		viewClasses.set(name, { name : name, cl : cl, position : position });
		return null;
	}

}