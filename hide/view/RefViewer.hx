package hide.view;

typedef Data = Array<{str:String, goto:()->Void}>;
class RefViewer extends hide.ui.View<Data> {

	public function new(state: Dynamic) {
		super(state);
	}

	override public function onDisplay() {
		showRefs([]);
	}

	public function showRefs(refs: Data) {
		element.html("");
		var div = new Element('<div class="refviewer hide-scroll">').appendTo(element);

		new Element('<p>Number of references : ${refs.length}</p>').appendTo(div);
		var ul = new Element('<ul>').appendTo(div);
		for (ref in refs) {
			var link = new Element('<li><a>${ref.str}</a></li>').appendTo(ul);
			if (ref.goto != null) {
				link.click((e) -> ref.goto());
			}
		}
	}

	static var _ = hide.ui.View.register(RefViewer, {position: Left, width: 300});
}