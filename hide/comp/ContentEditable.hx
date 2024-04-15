package hide.comp;

class ContentEditable extends Component {
	public var value(get, set) : String;
	public var spellcheck(never, set) : Bool;

	var html : js.html.Element = null;

	public function new(?parent : Element, ?element : Element) {
		if (element == null) {
			element = new Element("<div contenteditable></div>");
		}
		super(parent, element);

		html = element.get(0);

		var wasEdited = false;

		html.onfocus = function() {
			var range = js.Browser.document.createRange();
			range.selectNodeContents(html);
			var sel = js.Browser.window.getSelection();
			sel.removeAllRanges();
			sel.addRange(range);
		}
		html.onkeydown = function(e: js.html.KeyboardEvent) {
			if (e.keyCode == 13) {
				html.blur();
			}
			e.stopPropagation();
		}
		html.oninput = function(e) {
			if (!wasEdited) {
				wasEdited = true;
			}
		}
		html.onkeyup = function(e: js.html.KeyboardEvent) {
			e.stopPropagation();
		}
		html.onmousedown = function(e: js.html.PointerEvent) {
			e.stopPropagation();
		}
		html.onmousemove = function(e: js.html.PointerEvent) {
			e.stopPropagation();
		}
		html.onmouseup = function(e: js.html.PointerEvent) {
			e.stopPropagation();
		}

		html.onblur = function() {
			if (js.Browser.window.getSelection != null) {js.Browser.window.getSelection().removeAllRanges();}
			if (wasEdited) {
				onChange(get_value());
				wasEdited = false;
			}
		}
	}

	function set_value(v: String) {
		return html.innerText = v;
	}

	function set_spellcheck(v: Bool) {
		html.setAttribute("spellcheck", v ? "true" : "false");
		return v;
	}

	function get_value() {
		return html.innerText;
	}

	public dynamic function onChange(v: String) {};
}