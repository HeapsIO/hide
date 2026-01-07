package hide.kit;

#if domkit

class Text extends Element {
	public var content(default, set) : String;
	public var color(default, set) : KitColor;

	function set_color(v: KitColor) : KitColor {
		color = v;
		Element.setNativeColor(text, color);
		return color;
	}

	var text: NativeElement;

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
		Element.setNativeColor(text, color);
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

#end