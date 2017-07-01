package hide.ui;

@:keepSub
class View<T> {

	var ide : Ide;
	var container : golden.Container;
	var state : T;

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

	public function setContainer(cont) {
		this.container = cont;
		container.setTitle(getTitle());
		container.on("resize",function() {
			container.getElement().find('*').trigger('resize');
			onResize();
		});
	}

	public function onDisplay( j : js.jquery.JQuery ) {
		j.text(Type.getClassName(Type.getClass(this))+(state == null ? "" : " "+state));
	}

	public function onResize() {
	}

	public function saveState() {
		container.setState(state);
	}

	function get_contentWidth() return container.width;
	function get_contentHeight() return container.height;

	public static var viewClasses = new Array<Class<View<Dynamic>>>();
	public static function register<T>( cl : Class<View<T>> ) {
		viewClasses.push(cl);
		return null;
	}

}