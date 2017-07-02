package hide.view;

class About extends hide.ui.View<{}> {

	public function new(state) {
		super(state);
	}

	override function onDisplay( e : Element ) {
		e.html('
		<p>
			Heaps IDE v0.1<br/>
			(c)2017 Nicolas Cannasse
		</p>
		');
	}

	static var _ = hide.ui.View.register(About, Bottom);

}