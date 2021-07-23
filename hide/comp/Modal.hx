package hide.comp;

class Modal extends Component {

	public var content(default,null) : Element;
	var downTarget : Dynamic;
	var upTarget : Dynamic;

	public function new(?parent,?el) {
		super(parent,el);
		element.addClass('hide-modal');
		element.on("click dblclick keydown keyup keypressed mousedown mouseup mousewheel",function(e) e.stopPropagation());
		content = new Element("<div class='content'></div>").appendTo(element);

		var exterior = [element[0], content[0]];
		element[0].addEventListener("mousedown", function(e) {
			downTarget = e.target;
		}, true);
		element[0].addEventListener("mouseup", function(e) {
			upTarget = e.target;
		}, true);
		element.on("click", function(e : js.jquery.Event) {
			if( exterior.contains(downTarget) && exterior.contains(upTarget) ) {
				modalClick(e);
			}
		});
	}

	public dynamic function modalClick(e: js.jquery.Event) {
	}

	public function close() {
		element.remove();
	}

}