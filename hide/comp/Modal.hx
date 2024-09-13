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

class Modal2 extends Component {

	public var content: Element;
	var titleBar : Element;
	var titleElem : Element;

	public var title(default, set) : String;

	function set_title(v: String) : String{
		title = v;
		titleElem.text(title);
		return title;
	}

	public function new(?parent, title: String, saveKey: String) {
		saveDisplayKey = saveKey ?? "genericPopover";
		super(parent, new Element(
			'<hide-popover popover="auto">
				<title-bar>
					<div id="title"></div>
					<button id="close"><i class="ico ico-close"></i></button>
				</title-bar>
				<hide-content></hide-content>
			</hide-popover>'));

		titleBar = element.find('title-bar');
		titleElem = titleBar.find('#title');
		this.title = title;
		var closeButton = titleBar.find("#close");
		closeButton.click((e) -> close());
		content = element.find('hide-content');

		var size = getDisplayState("size");
		var html = element.get(0);
		if (size != null) {
			element.width(size.w);
			element.height(size.h);
		}
		untyped html.showPopover();
		html.addEventListener('toggle', toggle);
		html.addEventListener('beforetoggle', beforeToggle);
		html.addEventListener('dblclick', (ev:js.html.Event) -> {ev.preventDefault(); ev.stopPropagation(); trace("cathc");});
	}

	function beforeToggle(event: Dynamic) {
		if (event.newState == 'closed') {
			saveDisplayState("size", {w: element.width(), h: element.height()});
		}
	}

	function toggle(event: Dynamic) {
		if (event.newState == 'closed') {
			element.remove();
			onClose();
		}
	}

	public function close() {
		untyped element.get(0).hidePopover();
	}

	dynamic function onClose() {
		trace("close");
	}
}