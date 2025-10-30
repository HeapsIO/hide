package hide.kit;

class Text extends Element {
	var content(default, set) : String;

	#if js
	var text: NativeElement;
	#end

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
		text = js.Browser.document.createElement("kit-text");
		setupPropLine(null, text, false);
		refreshText();
		#else
		throw "HideKitHL Implement";
		#end
	}

	function refreshText() {
		#if js
		if (text != null)
			text.textContent = content;
		#else
		throw "HideKitHL Implement";
		#end
	}
}