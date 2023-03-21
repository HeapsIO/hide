package hide.view;

typedef Data = Array<{str:String, goto:()->Void}>;
class RefViewer extends hide.ui.View<Data> {
	var initialized = false;

	public function new(state: Dynamic) {
		super(state);
	}

	override public function onDisplay() {
		// avoid a race condition where showRefs would be called by other code then
		// onDisplay would clear the results
		if (initialized == false)
			showRefs([]);
	}

	public function showRefs(refs: Data, description: String = "Number of references") {
		element.html("");
		var div = new Element('<div class="refviewer hide-scroll">').appendTo(element);

		new Element('<p>$description : ${refs.length}</p>').appendTo(div);
		var ul = new Element('<ul>').appendTo(div);
		for (ref in refs) {
			var link = new Element('<li><a>${ref.str}</a></li>').appendTo(ul);
			if (ref.goto != null) {
				link.click((e) -> ref.goto());
			}
		}
		initialized = true;
	}

	static var _ = hide.ui.View.register(RefViewer, {position: Left, width: 300});
}