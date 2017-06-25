package hide.ui;

class View<T> {

	var state : T;

	public function new(state:T) {
		this.state = state;
	}

	public function getTitle() {
		var name = Type.getClassName(Type.getClass(this));
		return name.split(".").pop();
	}

	public function onDisplay( j : js.jquery.JQuery ) {
		j.html(Type.getClassName(Type.getClass(this)));
	}

}