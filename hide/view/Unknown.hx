package hide.view;

class Unknown extends hide.ui.View<{}> {

	override function onDisplay() {
		element.html('Component is no longer available <br/><pre>' + haxe.Json.stringify(state) + '</pre>');
	}

	static var _ = hide.ui.View.register(Unknown);

}