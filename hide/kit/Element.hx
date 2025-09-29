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
	var wrap: WrappedElement;

	/**
		Where wrapped children element should be added
	**/
	var wrapContent(get, never) : WrappedElement;


	inline function get_numChildren() return children?.length ?? 0;
	function get_wrapContent() return wrap;

	public function new(ctx: hide.prefab.EditContext, parent: Element, id: String) {
		this.editorContext = ctx;
		this.parent = parent;
		this.id = id;

		wrap = makeObject();

		if (this.parent != null) {
			this.parent.addChild(this);
		}
	}

	function makeObject() : WrappedElement {
		#if js
		var e = js.Browser.document.createDivElement();
		e.textContent = Type.getClassName(Type.getClass(this));
		return e;
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
			childBefore.wrap.before(newChild.wrap);
		} else {
			wrapContent.append(newChild.wrap);
		}
		#else
		throw "HideKitHL Implement";
		#end
	}


}