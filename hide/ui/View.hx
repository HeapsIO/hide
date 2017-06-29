package hide.ui;

class View<T> {

	var ide : Ide;
	var state : T;

	public function new(state:T) {
		this.state = state;
		ide = Ide.inst;
	}

	public function getTitle() {
		var name = Type.getClassName(Type.getClass(this));
		return name.split(".").pop();
	}

	public function onDisplay( j : js.jquery.JQuery ) {
		j.html(Type.getClassName(Type.getClass(this)));
	}

	public static var viewClasses = new Array<Class<View<Dynamic>>>();
	public static function register<T>( cl : Class<View<T>> ) {
		viewClasses.push(cl);
		return null;
	}

}