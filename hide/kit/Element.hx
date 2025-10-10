package hide.kit;

class Element {
	var parent(default, null) : Element;
	var id(default, null) : String;
	var properties(default, null) : hide.kit.Properties;

	var children : Array<Element> = null;
	public var numChildren(get, never) : Int;

	/**
		The underlying implementation element
	**/
	var native: NativeElement;

	/**
		Where native children element should be added
	**/
	var nativeContent(get, never) : NativeElement;


	inline function get_numChildren() return children?.length ?? 0;
	function get_nativeContent() return native;

	public function new(parent: Element, id: String) {
		this.parent = parent;
		this.properties = this.parent?.properties ?? Std.downcast(this.parent, Properties);

		this.id = ensureUniqueId(id);

		this.parent?.addChild(this);
		this.properties?.register(this);
	}

	public function make() {
		makeSelf();

		for (c in children ?? []) {
			c.make();
			attachNative(c);
		}
	}

	function ensureUniqueId(id: String) : String {
		if (this.properties == null)
			return id;
		var parentPath = this.parent != null ? this.parent.getIdPath() + "." : "";
		var count = 0;
		var newId = id;
		while (this.properties.getElementByPath(parentPath+newId) != null) {
			count ++;
			newId = id + count;
		}
		return newId;
	}

	public function getIdPath() {
		if (parent == null || parent is Properties)
			return id;
		return parent.getIdPath() + "." + id;
	}

	function makeSelf() : Void {
		#if js
		native = js.Browser.document.createDivElement();
		#else
		native = new hidehl.ui.Element();
		#end
	}

	function attachNative(child: Element) : Void {
		#if js
		child.native.remove();
		nativeContent.appendChild(child.native);
		#else
		child.native.remove();
		nativeContent.addChild(child.native);
		#end
	}

	public function addChild(newChild: Element) : Void {
		addChildAt(newChild, numChildren);
	}

	public function addChildAt(newChild: Element, position: Int) : Void {
		if (children == null)
			children = [];
		children.insert(position, newChild);
	}


}