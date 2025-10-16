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
		native = new hrt.ui.HuiElement();
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

	function addEditMenu(e: NativeElement) {
		#if js
		native.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
			e.preventDefault();
			e.stopPropagation();

			hide.comp.ContextMenu.createFromEvent(e, [
				{label: "Copy", click: copyToClipboard},
				{label: "Paste", click: pasteFromClipboard},
				{isSeparator: true},
				{label: "Reset", click: resetWithUndo},
			]
			);
		});
		#end
	}

	function setupPropLine(label: NativeElement, content: NativeElement) {
		#if js
		var parentLine = Std.downcast(parent, Line);

		if (parentLine == null) {
			native = js.Browser.document.createElement("kit-line");

			addEditMenu(native);

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
		#end
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

	function copyToClipboard() {
		#if js
		var data = {};
		copy(data);
		Ide.inst.setClipboard(haxe.Json.stringify(data));
		#end
	}

	function copy(target: Dynamic) {
		copySelf(target);

		if (children.length > 0) {
			target.children = {};
			for (child in children) {
				var subTarget = {};
				child.copy(subTarget);
				Reflect.setField(target.children, child.id, subTarget);
			}
		}
	}

	function copySelf(target: Dynamic) {

	}

	function pasteFromClipboard() {
		#if js
		var clipboard = Ide.inst.getClipboard();
		if (clipboard == null)
			return;

		var data = try {
			haxe.Json.parse(clipboard);
		} catch (e) {
			clipboard;
		}
		if (data == null)
			return;

		@:privateAccess root.prepareUndoPoint();

		switch(Type.typeof(data)) {
			case TObject, TClass(String):
				paste(data);
			default:
				try {
					var string = haxe.Json.stringify(data);
					paste(string);
				} catch(e) {
					Ide.inst.quickError(e);
				}
		}

		@:privateAccess root.finishUndoPoint();

		root.editor.refreshInspector();
		#end
	}

	function paste(data: Dynamic) {
		if (data is String) {
			pasteSelfString(data);
		} else {
			pasteSelf(data);
		}

		for (child in children) {
			if (data is String) {
				child.paste(data);
			} else {
				if (data.children != null) {
					var subData = Reflect.field(data.children, child.id);
					if (subData != null) {
						child.paste(subData);
					}
				}
			}
		}
	}

	function pasteSelf(data: Dynamic) {
	}

	function pasteSelfString(data: String) {
	}
}