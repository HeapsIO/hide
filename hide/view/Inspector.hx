package hide.view;

typedef InspectorState = {

}

class Inspector extends hide.ui.View<InspectorState> {

	override function new(state) {
		super(state);
	}
	override function onDisplay() {
		element.html("<p>Hello world</p>");
	}

	static var _ = hide.ui.View.register(Inspector, { width : 350, position : Right, id: "inspector" });
}