package hide.kit;

class Text extends Element {
	var content(default, set) : String;

	function set_content(v: String) : String {
		content = v;
		refreshText();
		return content;
	}

	public function new(parent: Element, id: String, content: String) : Void {
		super(parent, id);
		this.content = content;
	}

	override function makeSelf() : Void {
		#if js
		native = js.Browser.document.createElement("kit-text");
		refreshText();
		#else
		throw "HideKitHL Implement";
		#end
	}

	function refreshText() {
		#if js
		if (native != null)
			native.textContent = content;
		#else
		throw "HideKitHL Implement";
		#end
	}
}