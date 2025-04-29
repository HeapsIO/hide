package hide.view;

typedef FileBrowserState = {

}

class FileBrowser extends hide.ui.View<FileBrowserState> {

	override function new(state) {
		super(state);
	}
	override function onDisplay() {
		element.html("<p>Hello world</p>");
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}