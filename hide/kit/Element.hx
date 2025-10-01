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
		Where nativeped children element should be added
	**/
	var nativeContent(get, never) : NativeElement;


	inline function get_numChildren() return children?.length ?? 0;
	function get_nativeContent() return native;

	public function new(properties: hide.kit.Properties, parent: Element, id: String) {
		this.properties = properties;
		this.parent = parent;
		this.id = id;

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

	public function getIdPath() {
		if (parent == null || parent is Properties)
			return id;
		return parent.getIdPath() + "." + id;
	}

	function makeSelf() : Void {
		#if js
		native = js.Browser.document.createDivElement();
		#else
		throw "HideKitHL Implement";
		#end
	}

	function attachNative(child: Element) : Void {
		#if js
		child.native.remove();
		nativeContent.appendChild(child.native);
		#else
		throw "HideKitHL Implement";
		#end
	}

	public function addChild(newChild: Element) : Void {
		addChildAt(newChild, numChildren);
	}

	public function addChildAt(newChild: Element, position: Int) : Void {
		if (children == null)
			children = [];
		children.insert(position, newChild);
		// #if js
		// if (childBefore != null) {
		// 	childBefore.native.before(newChild.native);
		// } else {
		// 	nativeContent.append(newChild.native);
		// }
		// #else
		// throw "HideKitHL Implement";
		// #end
	}


}