package hide.comp;

class ContentEditable extends Component {
	public var value(get, set) : String;
	public var spellcheck(never, set) : Bool;

	var html : js.html.Element = null;
	var initialValue: String;

	public function new(?parent : Element, ?element : Element) {
		if (element == null) {
			element = new Element("<div contenteditable></div>");
		}
		super(parent, element);

		html = element.get(0);

		var wasEdited = false;

		html.onfocus = function() {
			var range = js.Browser.document.createRange();
			range.selectNodeContents(element.get(0));
			trace(element.get(0), range);
			var sel = js.Browser.window.getSelection();
			sel.removeAllRanges();
			sel.addRange(range);
			initialValue = value;
		}
		html.onkeydown = function(e: js.html.KeyboardEvent) {
			if (e.keyCode == 13) {
				html.blur();
			}
			if (e.key == "Escape") {
				value = initialValue;
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
			if (get_value() != initialValue) {
				onChange(get_value());
				wasEdited = false;
			}
			else {
				onCancel();
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

	public dynamic function onCancel() {};

	public dynamic function onChange(v: String) {};
}