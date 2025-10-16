package hide.kit;

class KitRoot extends Element {
	public var editedPrefabsProperties : Array<KitRoot> = [];
	var prefab : hrt.prefab.Prefab;
	var prefabUndoPoint : Dynamic = null;
	var edit : hide.prefab.EditContext;

	var registeredElements : Map<String, Element> = [];

	public function new(parent: Element, id: String, prefab: hrt.prefab.Prefab, editContext: hide.prefab.EditContext ) {
		super(parent, id);
		this.prefab = prefab;
		edit = editContext;
	}

	override function makeSelf() : Void {
		#if js
		native = js.Browser.document.createElement("kit-root");
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

	@:allow(hide.kit.Element)
	function broadcastValueChange(input: Widget<Dynamic>, isTemporaryEdit: Bool) {
		var idPath = input.getIdPath();

		prepareUndoPoint();

		input.onValueChange(isTemporaryEdit);
		prefab.updateInstance(input.id);

		for (childProperties in editedPrefabsProperties) {

			var childElement = childProperties.registeredElements.get(idPath);
			var childInput = Std.downcast(childElement, Type.getClass(input));

			if (childInput != null) {
				childInput.value = input.value;
				childInput.onValueChange(isTemporaryEdit);
				childProperties.prefab.updateInstance(input.id);
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
		#if js
		var sideEffects : Array<(isUndo:Bool) -> Void> = [];
		createUndoStep(sideEffects);

		for (childProperties in editedPrefabsProperties) {
			childProperties.createUndoStep(sideEffects);
		}

		if (sideEffects.length > 0) {
			edit.properties.undo.change(Custom((isUndo: Bool) -> {
				for (sideEffect in sideEffects) {
					sideEffect(isUndo);
				}
				Std.downcast(edit, hide.comp.SceneEditor.SceneEditorContext)?.rebuildProperties();
			}));
		}
		#end
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