package hide.kit;

#if domkit

/**
	# hrt.prefab.edit -> hrt.prefab.edit2 Migration notes

	- new function signature : edit2(ctx: hrt.prefab.EditContext2).
	- must be palced outside a `#if editor` block at the moment
	- new element creation syntax (replaces `new hide.Element("...")`):
		ctx.build(<element></element>);
	- multiple elements can be build at the same time in a ctx.build by putting them in a unique
		`<root></root>` container. This root container will not appear in the final element tree
		example :
			ctx.build(
				<root>
					<category("A")/>
					<category("B")/>
				</root>
			);
	- An optional onChange callback can be passed as the 3rd argument to ctx.build. If set, this function will be bound to all the onValueChange / onClick functions of the widgets in this ctx.build

	- `<div class="Group" name="Reference></div>` -> `<category("Reference")></category>`
	- `<dl></dl>` -> Nothing (this syntax is not needed anymore)
	- `<dt>Label</dt><dd><input type="range" field="x"></input><dd>` -> <slider label="Label" field={x}/>
		Note : if no label is specified, an automatic label will be generated from its field expression if possible, automatically adding caps and spaces if needed (i.e a "fooBar" field creates a "Foo Bar" label)
	- Widget conversion suggestions :
		`<input type="button" value="Button Name"/>` -> `<button("Button Name")/>`
			Note : to bind a callback, use the onClick attribute on the button, or add an id to the button and add the callback later
		`<input type="range" min="0" max="360"/>` -> `<range(0, 360)/>`
		`<input type="text">` -> `<input/>`
		`<select></select>` -> `<select(["Choice 1", "Choice 2"])/>`
			Note : the option list can either be a string or an Array<{value: Dynamic, label: String}>. A string array will automatically be converted in a value/label string using the string as the value and the label. The widget `value` will be equal to the `value` of the currently selected item
			Additionally, if the field is an enum, a list of values generated from the enum possible values is generated automatically if you don't supply an option list
		`<input type="texturepath"/>` -> `<file type="texture">` if you don't want to support gratiend (95% of non shader use-cases), otherwise use a `<texture/>`
		`<input type="fileselect" extensions="..."/>` -> `<file type="type_name"/>` The list of allowed type can be found in hide.kit.File.types, you can add more types to the list if needed
		`<p>Info message</p>` -> `<text("Info message")/>`

	- Editor api conversions :
		`ctx.rebuildProperties()` -> `ctx.rebuildInspector()`
		`shaded.editor.refreshInteractive(this)` -> `ctx.rebuildPrefab(this)`;
		`shaded.editor.refreshTree(All)` -> `ctx.rebuildTree(this)`;
		`ctx.rebuildPrefab(this)` -> `ctx.rebuildPrefab(this)`;
		`<input title="Tooltip"/>` -> `<element tooltip="Tooltip"/>`
		Callbacks bound in the onChange function should be bound on the relevant widget onValueChange instead
	**/

@:keepSub
class Element {
	#if !macro
	/**
		If set, the element and its children will be disabled when editing more than one prefab at the time.
	**/
	public var singleEdit : Bool = false;

	/**
		If set, the element and its children can't be edited and will be grayed out
		use isDisabled to know if this element is editable or not (because it depend on the disabled state of it's parent)
	**/
	public var disabled(default, set) = false;

	/**
		If set, the element will take width units of space in its line
	**/
	public var width : Null<Int> = null;

	/**
		If set, add a tooltip on hover for this element
	**/
	public var tooltip : String = null;


	/**
		Internal ID of this element that is unique between this element siblings (use getIdPath for a unique identifier in this element tree)
	**/
	public var id(default, null) : String;

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

	public function getChildren() : haxe.ds.ReadOnlyArray<Element> {
		return children;
	}

	inline function get_numChildren() return children.length;
	function get_nativeContent() return native;
	function set_disabled(v: Bool) {
		disabled = v;
		refreshDisabled();
		return disabled;
	}

	function isDisabled() {
		if (parent != null)
			return disabled || parent.getChildDisabled();
		return disabled;
	}

	function getChildDisabled() {
		return isDisabled();
	}

	public function new(parent: Element, id: String) {
		this.parent = parent;
		this.root = this.parent?.root ?? Std.downcast(this.parent, KitRoot);

		this.id = makeUniqueId(id);

		this.parent?.addChild(this);
	}

	/**
		Create the native elements of this Element to be displayed in the editor
	**/
	public function make(attach: Bool = true) {
		if (singleEdit && root.isMultiEdit)
			disabled = true;

		makeSelf();
		#if hui
		if (native == null) {
			native = new hrt.ui.HuiText('missing makeSelf implem for ${Type.getClassName(Type.getClass(this))}');
		}
		#end

		if (attach && parent != null)
			parent.attachChildNative(this);

		// call setters
		disabled = disabled;

		makeChildren();

		#if js
		if (native != null && tooltip != null) {
			native.title = tooltip;
		}
		#end
	}

	/**
		Get a path uniquely identifying this Element from the root
	**/
	public function getIdPath() {
		if (parent == null || parent is KitRoot)
			return id;
		return parent.getIdPath() + "." + id;
	}

	/**
		Find the first element that has the given id in this element children, recursive
	**/
	public function getById<T:Element>(id: String, ?cl: Class<T>) : T {
		if (this.id == id) {
			var asCl = cl != null ? Std.downcast(this, cl) : cast this;
			if (asCl != null)
				return asCl;
		}

		for (child in children) {
			var found = child.getById(id);
			if (found != null)
				return found;
		}
		return null;
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
		#elseif hui
		native = new hrt.ui.HuiElement();
		#end
	}


	// Overridable API

	function makeChildren() {
		for (c in children) {
			c.disabled = c.disabled || disabled;
			c.make();
		}
	}

	function getEditMenuContent() : Array<hide.comp.ContextMenu.MenuItem> {
		return [
			{label: "Copy", click: copyToClipboard, enabled: canCopy()},
			{label: "Paste", click: pasteFromClipboard, enabled: canPaste()},
			{isSeparator: true},
			{label: "Reset", click: resetWithUndo, enabled: canReset()}
		];
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
		newChild.parent = this;
		newChild.root = this.root;
	}

	function addEditMenu(e: NativeElement) {
		#if js
		if (!disabled) {
			native.addEventListener("contextmenu", (e: js.html.MouseEvent) -> {
				if ((cast e.target:js.html.Element).closest(".is-cdb-editor") != null)
					return;
				e.preventDefault();
				e.stopPropagation();

				hide.comp.ContextMenu.createFromEvent(e, getEditMenuContent());
			});
		}
		#end
	}

	function canCopy() : Bool {
		for (child in children) {
			if (child.canCopy())
				return true;
		}
		return false;
	}

	function canPaste() : Bool {
		for (child in children) {
			if (child.canPaste())
				return true;
		}
		return false;
	}

	function canReset() : Bool {
		for (child in children) {
			if (child.canReset())
				return true;
		}
		return false;
	}

	public function collapse() {
		for (child in children) {
			child.collapse();
		}
	}

	/**
		Create a line in the inspector, with the given label (on the left) and content (on the right).
		If the element is already in the line, the function correclty handle that and create the appropriate
		element instead.
	**/
	function setupPropLine(label: NativeElement, content: NativeElement, autoCreateLabel: Bool = true, bigContent: Bool = false) {
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
			setupLabelReset(label);
			native.appendChild(label);
		}
		if (content != null) {
			native.appendChild(content);
			if (width != null)
				native.style.setProperty('--width', '$width');
		}
		#end
	}

	function setupLabelReset(label: NativeElement) {
		#if js
		label.onclick = (e: js.html.MouseEvent) -> {
			if (e.button == 0) {
				resetWithUndo();
			}
		};
		#end
	}

	/**
		If the first child of this element can have a label, add it to label and remove it from the child
	**/
	function stealChildLabel(target: NativeElement) {
		#if js
		var childWidget = Std.downcast(children[0], Widget);
		if (childWidget != null) {
			if (childWidget.label != null && childWidget.label.length > 0) {
				var span = js.Browser.document.createSpanElement();
				span.innerText = childWidget.label;
				target.appendChild(span);
				childWidget.label = null;
			}
		}
		#end
	}

	function change(callback: () -> Void, isTemporary: Bool) {
		if (parent != null) {
			parent.change(callback, isTemporary);
		}
	}

	/**
		Place `element` between this and this.parent
		Only guaranteed to work if the widget hasn't been made yet
	**/
	function wrapWith(element: Element) : Void {
		var index = this.parent.children.indexOf(this);
		parent.addChildAt(element, index);
		this.parent.children.remove(this);
		element.addChild(this);
	}

	/**
		Get the line of this widget, or wrap this widget in one if it doesn't exist
		Only guaranteed to work if the widget hasn't been made yet
	**/
	public function getOrMakeLine() : Line {
		var p = this;
		while(p != null) {
			if (Std.downcast(p, Line) != null)
				return cast p;
			p = p.parent;
		}
		var line = new Line(null, null);
		wrapWith(line);
		return line;
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
		#elseif hui
		nativeContent.addChild(child.native);
		#end
	}

	function setEnabled(enabled: Bool) : Void {
		this.disabled = !enabled;
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
		Find the child of this element that has the given id. Not recursive
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

	function refreshDisabled() {
		#if js
		if (native != null) {
			native.classList.toggle("disabled", isDisabled());
		}
		#end
		for (child in children) {
			child.refreshDisabled();
		}
	}

	/**
		Create elements from a runtime propsDef to edit the
	**/
	public function buildPropsList(defs: Array<hrt.prefab.Props.PropDef>, props: Dynamic) : Void {
		if (props == null)
			throw "Props shouldn't be null";
		for (def in defs) {
			buildProp(def, props);
		}
	}

	public function buildProp(def: hrt.prefab.Props.PropDef, props: Dynamic) : Void {
		var defValue: Dynamic = null;
		var widget : hide.kit.Widget<Dynamic> = switch(def.t) {
			case PInt(min, max):
				var slider = new hide.kit.Slider(this, def.name);
				slider.min = min;
				slider.max = max;
				slider.int = true;
				@:privateAccess slider.showRange = min != null && max != null;
				slider;
			case PFloat(min, max):
				var slider = new hide.kit.Slider(this, def.name);
				slider.min = min;
				slider.max = max;
				@:privateAccess slider.showRange = min != null && max != null;
				slider;
			case PBool:
				new hide.kit.Slider(this, def.name);
			case PTexturePath:
				var file = new hide.kit.File(this, def.name);
				file.type = "texture";
				file;
			case PTexture:
				new hide.kit.Texture(this, def.name);
			case PColor:
				var color = new hide.kit.Color(this, def.name);
				color.arr = true;
				defValue = [0,0,0,1];
				color;
			case PGradient:
				new hide.kit.Gradient(this, def.name);
			case PUnsupported(debug):
				var text = new hide.kit.Text(this, def.name, debug);
				text.color = Red;
				null;
			case PVec(n, min, max):
				var isColor = def.name.toLowerCase().indexOf("color") >= 0;
				if(isColor && (n == 3 || n == 4)) {
					var color = new hide.kit.Color(this, def.name);
					color.arr = true;
					defValue = [];
					color.alpha = n == 4;
					color;
				} else {
					var line = new Line(this, def.name);
					line.label = def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
					var vec : Array<Dynamic> = Reflect.field(props, def.name);
					if (vec == null) {
						vec = [];
						Reflect.setField(props, def.name, vec);
					}
					vec.resize(n);
					for (i in 0...n) {
						var slider = new Slider(line, '${def.name}.i');
						slider.label = ["X", "Y", "Z", "W"][i];
						slider.value = vec[i];
						slider.min = min;
						slider.max = max;
						@:privateAccess slider.showRange = min != null && max != null;
						@:privateAccess slider.onFieldChange = (_) -> {
							vec[i] = slider.value;
						}
					}
					null;
				}
			case PChoice(choices):
				new hide.kit.Select(this, def.name, choices);
			case PEnum(en):
				var select = new hide.kit.Select(this, def.name);
				var entries = [];
				for (constructor in haxe.EnumTools.getConstructors(en)) {
					entries.push({value: haxe.EnumTools.createByName(en, constructor), label: hide.kit.Macros.camelToSpaceCase(constructor)});
				}

				select.setEntries(entries);
				select;
			case PFile(exts):
				var file = new File(this, def.name);
				file.exts = exts;
				file;
			case PString(len):
				new Input(this, def.name);
		}
		if (widget != null) {
			widget.label =  def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
			widget.value = Reflect.field(props, def.name) ?? defValue;
			@:privateAccess widget.onFieldChange = (_) -> {
				Reflect.setField(props, def.name, widget.value);
			};
		}
	}

	public function remove() {
		if (parent != null) {
			parent.children.remove(this);
		}
		this.parent = null;
	}

	static public function setNativeColor(element: NativeElement, color: KitColor) {
		#if js
		if (element != null) {
			element.classList.toggle("color-red", color == Red);
			element.classList.toggle("color-orange", color == Orange);
			element.classList.toggle("color-yellow", color == Yellow);
			element.classList.toggle("color-green", color == Green);
			element.classList.toggle("color-cyan", color == Cyan);
			element.classList.toggle("color-blue", color == Blue);
			element.classList.toggle("color-purple", color == Purple);
		}
		#end
	}

	#end

	/**
		Create elements from a DML expression and append them at the end of this element
	**/
	public macro function build(ethis: haxe.macro.Expr, dml: haxe.macro.Expr, ?contextObj: haxe.macro.Expr, ?onAnyChange: haxe.macro.Expr.ExprOf<(isTemp:Bool) -> Void>) : haxe.macro.Expr {
		return hide.kit.Macros.build(ethis, dml, contextObj, onAnyChange);
	}
}

#end