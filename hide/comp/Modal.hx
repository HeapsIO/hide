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

		var exterior = [element.get(), content.get()];
		element.get(0).addEventListener("mousedown", function(e) {
			downTarget = e.target;
		}#if js, true #end);
		element.get(0).addEventListener("mouseup", function(e) {
			upTarget = e.target;
		}#if js, true #end);
		element.on("click", function(e : Element.Event) {
			if( exterior.contains(downTarget) && exterior.contains(upTarget) ) {
				modalClick(e);
			}
		});
	}

	public dynamic function modalClick(e: Element.Event) {
	}

	public function close() {
		element.remove();
	}

}