package hide.kit;

@:keepSub
class Element {
	var parent(default, null) : Element;
	var id(default, null) : String;
	var root(default, null) : hide.kit.KitRoot;

	var children : Array<Element> = [];
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
		this.root = this.parent?.root ?? Std.downcast(this.parent, KitRoot);

		this.id = ensureUniqueId(id);

		this.parent?.addChild(this);
		this.root?.register(this);
	}

	public function make() {
		makeSelf();

		for (c in children) {
			c.make();
			attachNative(c);
		}
	}

	function ensureUniqueId(id: String) : String {
		if (this.root == null)
			return id;
		var parentPath = this.parent != null ? this.parent.getIdPath() + "." : "";
		var count = 0;
		var newId = id;
		while (this.root.getElementByPath(parentPath+newId) != null) {
			count ++;
			newId = id + count;
		}
		return newId;
	}

	public function getIdPath() {
		if (parent == null || parent is KitRoot)
			return id;
		return parent.getIdPath() + "." + id;
	}

	function makeSelf() : Void {
		#if js
		native = js.Browser.document.createDivElement();
		#else
		native = new hidehl.ui.HuiElement();
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

	function setupPropLine(label: NativeElement, content: NativeElement) {
		var parentLine = Std.downcast(parent, Line);

		if (parentLine == null) {
			native = js.Browser.document.createElement("kit-line");

			native.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
				e.preventDefault();
				e.stopPropagation();

				hide.comp.ContextMenu.createFromEvent(e, [
					{label: "Reset", click: resetWithUndo},
				]
				);
			});

		} else {
			native = js.Browser.document.createElement("kit-div");
		}

		if (label == null) {
			label = js.Browser.document.createElement("kit-label");
		}

		if (label != null) {
			if (parentLine == null) {
				label.classList.add("first");
			} else if(parent.children[0] == this && parentLine.label == null && !parentLine.full) {
				label.classList.add("first");
				parentLine.labelElement.remove();
			}
			native.appendChild(label);
		}
		if (content != null)
			native.appendChild(content);
	}

	function resetWithUndo() {
		@:privateAccess root.prepareUndoPoint();

		reset();

		@:privateAccess root.finishUndoPoint();
	}

	function reset() {
		for (child in children) {
			child.reset();
		}
	}


}