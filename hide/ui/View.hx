package hide.ui;

class View<T> {

	var ide : Ide;
	var container : golden.Container;
	var state : T;

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
	}

	public function onDisplay( j : js.jquery.JQuery ) {
		j.text(Type.getClassName(Type.getClass(this))+(state == null ? "" : " "+state));
	}

	public function saveState() {
		container.setState(state);
	}

	public static var viewClasses = new Array<Class<View<Dynamic>>>();
	public static function register<T>( cl : Class<View<T>> ) {
		viewClasses.push(cl);
		return null;
	}

}