package hide.kit;

/**
	# Migration notes

	1. Nouvelle signature : edit2(ctx: hrt.prefab.EditContext2).
	2. A placer en dehors d'un block #if editor
	3. Nouvelle syntaxe pour créer un bloc de ui :
		ctx.build(<element></element>);

	4. `<div class="Group" name="Reference></div>` -> `<category("Reference")></category>`
	5. `<dl></dl>` -> Rien du tout (ne sert plus à rien)
	6. `<dt>Label</dt><dd><input type="range" field="x"></input><dd>` -> <slider label="Label" field={x}/>
		Note : si le label est identique au field, pas besoin de préciser (le field sera transformé en label automatiquement, avec des majuscules et des espaces)
	7. Conversion des types d'input
		`<input type="button" value="Nom du bouton"/>` -> `<button("Nom du boutton")/>`
		`<input type="range" min="0" max="360"/>` -> `<range(0, 360)/>`
		`<input type="text">` -> `<input/>`
		`<select></select>` -> `<select(["Choix 1", "Choix 2"])/>`
			Note : la liste d'option peut soit être une liste de string, soit une liste d'objets {value: Dynamic, label: String}. La premiere sera automatiquement convertie dans le second format avec la string en valeur et en label. La valeur du widget Select sera égal a la `value` de l'item acutellement selectionné
		`<input type="texturepath"/>` -> `<file type="texture">` si vous ne voulez pas que l'utilisateur puisse passer un gradient généré par l'éditeur (95% des cas hors shader) ou `<texture/>`
		`<input type="fileselect" extensions="..."/>` -> Trouver ou ajouter les extensions dans hide.kit.File.types, puis `<file type="nom_du_type"/>`
		`<p>Message d'information</p>` -> `<text("Message d'information")/>`

	8. Conversion d'api Editeur :
		`ctx.rebuildProperties()` -> `ctx.rebuildInspector()`
		`shaded.editor.refreshInteractive(this)` -> `ctx.rebuildPrefab(this)`;
		`shaded.editor.refreshTree(All)` -> `ctx.rebuildTree(this)`;
		`ctx.rebuildPrefab(this)` -> `ctx.rebuildPrefab(this)`;
		Les callbacks qui sont bind dans le onChange sont plutot à placer sur le onValueChange des widgets**/



@:keepSub
class Element {
	#if !macro
	/**
		If set, the element and its children will be disabled when editing more than one prefab at the time.
	**/
	public var singleEdit : Bool = false;

	/**
		If set, the element and its children can't be edited and will be grayed out
	**/
	public var disabled = false;


	/**
		Internal ID of this element that is unique between this element siblings (use getIdPath for a unique identifier in this element tree)
	**/
	var id(default, null) : String;

	var root(default, null) : hide.kit.KitRoot;
	var parent(default, null) : Element;

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

	inline function get_numChildren() return children.length;
	function get_nativeContent() return native;

	public function new(parent: Element, id: String) {
		this.parent = parent;
		this.root = this.parent?.root ?? Std.downcast(this.parent, KitRoot);

		this.id = makeUniqueId(id);

		this.parent?.addChild(this);
	}

	/**
		Create the native elements of this Element to be displayed in the editor
	**/
	public function make() {
		if (singleEdit && root.isMultiEdit)
			disabled = true;

		makeSelf();

		if (parent != null)
			parent.attachChildNative(this);

		setEnabled(!disabled);

		for (c in children) {
			c.disabled = c.disabled || disabled;
			c.make();
		}
	}

	/**
		Get a path uniquely identifying this Element from the root
	**/
	public function getIdPath() {
		if (parent == null || parent is KitRoot)
			return id;
		return parent.getIdPath() + "." + id;
	}

	// Overridable API

	/**
		Called to reset to their default value this Element values
	**/
	function resetSelf() : Void {}

	/**
		Load values from data onto this element values. Data is garanteed to be a Dynamic object (but it's content can be anything)
	**/
	function pasteSelf(data: Dynamic) {}

	/**
		Load value from a string onto this object. Done when the used copied a string from somewhere else instread of copying it from the editor
	**/
	function pasteSelfString(data: String) {}

	/**
		Make a copy of this element values and store them in target (not recursive)
	**/
	function copySelf(target: Dynamic) {}

	/**
		Create the nativeElement for this Element.
		This should set the "native" field to the created element
	**/
	function makeSelf() : Void {
		#if js
		native = js.Browser.document.createDivElement();
		#else
		native = new hrt.ui.HuiElement();
		#end
	}

	// Internal API

	/**
		At the moment adding / removing child dynamically after the make is not supported.
	**/
	function addChild(newChild: Element) : Void {
		addChildAt(newChild, numChildren);
	}

	function addChildAt(newChild: Element, position: Int) : Void {
		children.insert(position, newChild);
	}

	function addEditMenu(e: NativeElement) {
		#if js
		if (!disabled) {
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
		}
		#end
	}

	/**
		Create a line in the inspector, with the given label (on the left) and content (on the right).
		If the element is already in the line, the function correclty handle that and create the appropriate
		element instead.
	**/
	function setupPropLine(label: NativeElement, content: NativeElement, autoCreateLabel: Bool = true) {
		#if js
		var parentLine = Std.downcast(parent, Line);

		if (parentLine == null) {
			native = js.Browser.document.createElement("kit-line");

			addEditMenu(native);

		} else {
			native = js.Browser.document.createElement("kit-div");
		}

		if (label == null && autoCreateLabel) {
			label = js.Browser.document.createElement("kit-label");
		}

		if (label != null) {
			if (parentLine == null) {
				label.classList.add("first");
			}
			native.appendChild(label);
		}
		if (content != null)
			native.appendChild(content);
		#end
	}

	/**
		If the first child of this element can have a label, add it to label and remove it from the child
	**/
	function stealChildLabel(target: NativeElement) {
		var childWidget = Std.downcast(children[0], Widget);
		if (childWidget != null) {
			if (childWidget.label != null && childWidget.label.length > 0) {
				var span = js.Browser.document.createSpanElement();
				span.innerText = childWidget.label;
				target.appendChild(span);
				childWidget.label = null;
			}
		}
	}

	final function resetWithUndo() {
		@:privateAccess root.prepareUndoPoint();

		reset();

		@:privateAccess root.finishUndoPoint();
	}

	/**
		Reset this element and it's element children to their default values
	**/
	function reset() {
		resetSelf();

		for (child in children) {
			child.reset();
		}
	}

	/**
		Copy this element value and its children to the clipboard
	**/
	final function copyToClipboard() {
		#if js
		var data = {};
		copy(data);
		Ide.inst.setClipboard(haxe.Json.stringify(data));
		#end
	}

	/**
		Make a copy of this element values and its children and store them in target
	**/
	final function copy(target: Dynamic) {
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

	final function pasteFromClipboard() {
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

		root.editor.rebuildInspector();
		#end
	}

	/**
		Load values present in data in this element values. Data can either be a String or a Dynamic object
	**/
	final function paste(data: Dynamic) {
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

	function attachChildNative(child: Element) : Void {
		#if js
		nativeContent.appendChild(child.native);
		#else
		nativeContent.addChild(child.native);
		#end
	}

	function setEnabled(enabled: Bool) : Void {
		this.disabled = !enabled;
		#if js
		nativeContent.classList.toggle("disabled", disabled);
		#else

		#end
	}

	/**
		Return a key used to store settings for this particular element (identified by the id)
	**/
	function getSaveKey(category: hrt.prefab.EditContext2.SettingCategory, key: String) {
		switch (category) {
			case Global:
				return '$id/$key';
			case SameKind:
				return '${getIdPath()}/$key';
		}
	}

	/**
		Save a setting value from `data` identified with `key` for this particular element in the local storage
	**/
	function saveSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String, data: Dynamic) : Void {
		root.editor.saveSetting(category, getSaveKey(category, key), data);
	}

	/**
		Retrieve a setting identified with `key` for this particular element in the local storage.
		Returns null if the value is not set
	**/
	function getSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String) : Dynamic {
		return root.editor.getSetting(category, getSaveKey(category, key));
	}

	/**
		Find the child of this element that has the given id. Not reccursive
	**/
	function getChildById(id: String) : Element {
		for (child in children) {
			if (child.id == id) {
				return child;
			}
		}
		return null;
	}

	function makeUniqueId(id: String) : String {
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
	#end

	public macro function build(ethis: haxe.macro.Expr, dml: haxe.macro.Expr, ?contextObj: haxe.macro.Expr) : haxe.macro.Expr {
		return hide.kit.Macros.build(ethis, dml, contextObj);
	}
}