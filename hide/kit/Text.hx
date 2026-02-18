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

	var text: #if hui hrt.ui.HuiText #else NativeElement #end;

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
		#elseif hui
		text = new hrt.ui.HuiText();
		setupPropLine(null, text, false);
		refreshText();
		#end
		Element.setNativeColor(text, color);
	}

	function refreshText() {
		#if js
		if (text != null)
			text.get().textContent = content;
		#elseif hui
		if (text != null)
			text.text = content;
		#end
	}
}

#end