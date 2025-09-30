package hide.kit;

class Element {
	var parent(default, null) : Element;
	var id(default, null) : String;
	var editorContext(default, null) : hide.prefab.EditContext;

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

	public function new(ctx: hide.prefab.EditContext, parent: Element, id: String) {
		this.editorContext = ctx;
		this.parent = parent;
		this.id = id;

		native = makeNative();

		if (this.parent != null) {
			this.parent.addChild(this);
		}
	}

	function makeNative() : NativeElement {
		#if js
		return js.Browser.document.createDivElement();
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
		var childBefore = children[position];
		children.insert(position, newChild);
		#if js
		if (childBefore != null) {
			childBefore.native.before(newChild.native);
		} else {
			nativeContent.append(newChild.native);
		}
		#else
		throw "HideKitHL Implement";
		#end
	}


}