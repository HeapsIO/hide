package hide.kit;

typedef NativeElementType = #if js js.html.Element #else h2d.Object #end;
abstract NativeElement(NativeElementType) from NativeElementType to NativeElementType {

	public function addClass(name: String) {
		#if js
		this.classList.add(name);
		#elseif hui
		this.dom.addClass(name);
		#end
	}

	public function toggleClass(name: String, ?force: Bool) {
		#if js
		this.classList.toggle(name, force);
		#elseif hui
		this.dom.toggleClass(name, force);
		#end
	}


	public function get() : NativeElementType {
		return this;
	}

	public function addChild(other: NativeElement) {
		#if js
		this.appendChild(other);
		#else
		this.addChild(other);
		#end
	}

	public static function create(kind: String) : NativeElement {
		#if js
		return js.Browser.document.createElement(kind);
		#elseif hui
		var elem = new hrt.ui.HuiElement();
		elem.dom.addClass(kind);
		return elem;
		#else
		return null;
		#end
	}
}

