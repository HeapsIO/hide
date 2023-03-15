package hide.view;

enum Info {
	Script(line: Int);
	Cell(sheet: cdb.Sheet, line: Int, column : Int, ?scriptLine: Int);
}

class Data {
	var refs : Array<Info>;
}

class RefViewer extends hide.ui.View<Data> {
	public function new(state: Data) {
		super(state);
	}

	override function onDisplay() {
		element.append(new Element("<p> hello worlds ?</p>"));
	}

	static var _ = hide.ui.View.register(RefViewer, {position: Bottom, width: 100});
}