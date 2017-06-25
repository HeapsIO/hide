package hide.view;

class About extends hide.ui.View<{}> {

	public function new(state) {
		super(state);
	}

	override function onDisplay(j:js.jquery.JQuery) {
		j.html('
		<p>
			Heaps IDE v0.1<br/>
			(c)2017 Nicolas Cannasse
		</p>
		');
	}

}