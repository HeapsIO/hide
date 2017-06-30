package hide.comp;

class ScrollZone extends Component {

	public var content : Element;

	public function new(root) {
		super(root);
		content = new Element("<div class='hide_scrollzone'>").appendTo(root);
	}

}