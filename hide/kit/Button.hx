package hide.kit;

class Button extends Element {
	var label : String;
	public var highlight(default, set) : Bool = false;
	var button : NativeElement;

	function set_highlight(v:Bool) : Bool {
		highlight = v;
		syncHightlight();
		return v;
	}

	public function new(parent: Element, id: String, label: String) {
		super(parent, id);
		this.label = label;
	}

	public dynamic function onClick() {

	}

	function broadcastClick() {
		properties.broadcastClick(this);
	}

	override function makeSelf() {
		#if js
		var parentLine = Std.downcast(parent, Line);

		if (parentLine == null) {
			native = js.Browser.document.createElement("kit-line");
		} else {
			native = js.Browser.document.createElement("kit-div");
		}

		button = js.Browser.document.createElement("kit-button");
		button.innerHTML = label;
		native.appendChild(button);
		button.addEventListener("click", (e:js.html.MouseEvent) -> {
			broadcastClick();
			e.preventDefault();
			e.stopPropagation();
		});

		syncHightlight();
		#else

		#end
	}

	function syncHightlight() {
		#if js
		if (button != null)
			button.classList.toggle("highlight", highlight);
		#end
	}
}