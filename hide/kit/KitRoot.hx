package hide.kit;

class KitRoot extends Element {
	public var editedPrefabsProperties : Array<KitRoot> = [];
	var prefab : hrt.prefab.Prefab;
	var prefabUndoPoint : Dynamic = null;
	public var editor(default, null) : EditorAPI;

	var registeredElements : Map<String, Element> = [];

	public function new(parent: Element, id: String, prefab: hrt.prefab.Prefab, editor: EditorAPI ) {
		super(parent, id);
		this.prefab = prefab;
		this.editor = editor;
		root = root ?? this;
	}

	override function makeSelf() : Void {
		#if js
		native = js.Browser.document.createElement("kit-root");

		var toolbar = js.Browser.document.createElement("kit-toolbar");
		native.appendChild(toolbar);
		var copyButton = new hide.Element('<fancy-button title="Copy all properties">').append(new hide.Element('<div class="icon ico ico-copy">'))[0];
		toolbar.appendChild(copyButton);
		copyButton.addEventListener("click", (e: js.html.MouseEvent) -> {
			copyToClipboard();
		});

		var pasteButton = new hide.Element('<fancy-button title="Paste values from the clipboard">').append(new hide.Element('<div class="icon ico ico-paste">'))[0];
		toolbar.appendChild(pasteButton);
		pasteButton.addEventListener("click", (e: js.html.MouseEvent) -> {
			pasteFromClipboard();
		});


		#else
		native = new hrt.ui.HuiElement();
		native.dom.addClass("root");
		#end
	}

	public function register(element: Element) {
		registeredElements.set(element.getIdPath(), element);
	}

	public function getElementByPath(id: String) {
		return registeredElements.get(id);
	}

	@:allow(hide.kit.Widget)
	function broadcastValuesChange(inputs: Array<Widget<Dynamic>>, isTemporaryEdit: Bool) {

		prepareUndoPoint();

		for(input in inputs) {
			input.onValueChange(isTemporaryEdit);
			prefab.updateInstance(input.id);
		}

		for (input in inputs) {
			var idPath = input.getIdPath();
			for (childProperties in editedPrefabsProperties) {
				var childElement = childProperties.registeredElements.get(idPath);
				var childInput = Std.downcast(childElement, Type.getClass(input));

				if (childInput != null) {
					childInput.value = input.value;
					childInput.onValueChange(isTemporaryEdit);
					childProperties.prefab.updateInstance(input.id);
				}
			}
		}

		if (!isTemporaryEdit) {
			finishUndoPoint();
		}
	}

	@:allow(hide.kit.Element)
	function broadcastClick(button: Button) {
		var idPath = button.getIdPath();

		prepareUndoPoint();

		button.onClick();
		prefab.updateInstance();

		for (childProperties in editedPrefabsProperties) {

			var childElement = childProperties.registeredElements.get(idPath);
			var childButton = Std.downcast(childElement, Button);
			if (childButton != null) {
				childButton.onClick();
				childProperties.prefab.updateInstance();
			}
		}

		finishUndoPoint();
	}

	/**
		Creates an undoPoint for the currently edited prefabs if none exists
	**/
	function prepareUndoPoint() : Void {
		if (prefabUndoPoint == null) {
			prefabUndoPoint = hrt.prefab.Diff.deepCopy(prefab.save());
			for (childProperties in editedPrefabsProperties) {
				childProperties.prefabUndoPoint = hrt.prefab.Diff.deepCopy(childProperties.prefab.save());
			}
		}
	}

	function finishUndoPoint() {
		var sideEffects : Array<(isUndo:Bool) -> Void> = [];
		createUndoStep(sideEffects);

		for (childProperties in editedPrefabsProperties) {
			childProperties.createUndoStep(sideEffects);
		}

		if (sideEffects.length > 0) {
			editor.recordUndo((isUndo: Bool) -> {
				for (sideEffect in sideEffects) {
					sideEffect(isUndo);
				}
				editor.refreshInspector();
			});
		}
	}

	function createUndoStep(sideEffects : Array<(isUndo:Bool) -> Void>) : Void {
		var before = prefabUndoPoint;
		prefabUndoPoint = null;
		var after = prefab.save();
		if (hrt.prefab.Diff.diff(before, after) != Skip) {
			sideEffects.push((isUndo) -> {
				if (isUndo) {
					prefab.load(before);
				} else {
					prefab.load(after);
				}
				prefab.updateInstance();
			});
		}
	}
}