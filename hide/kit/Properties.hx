package hide.kit;

class Properties extends Element {
	public var editedPrefabsProperties : Array<Properties> = [];
	var prefab : hrt.prefab.Prefab;
	var prefabUndoPoint : Dynamic = null;
	var edit : hide.prefab.EditContext;

	var registeredElements : Map<String, Element> = [];

	public function new(properties: hide.kit.Properties, parent: Element, id: String, prefab: hrt.prefab.Prefab, editContext: hide.prefab.EditContext ) {
		super(properties, parent, id);
		this.prefab = prefab;
		edit = editContext;
	}

	public function register(element: Element) {
		registeredElements.set(element.getIdPath(), element);
	}

	public function broadcastValueChange(input: Input<Dynamic>, isTemporaryEdit: Bool) {
		var idPath = input.getIdPath();

		if (prefabUndoPoint == null) {
			prefabUndoPoint = prefab.save();
			for (childProperties in editedPrefabsProperties) {
				childProperties.prefabUndoPoint = childProperties.prefab.save();
			}
		}

		input.onValueChange(isTemporaryEdit);

		for (childProperties in editedPrefabsProperties) {

			var childElement = childProperties.registeredElements.get(idPath);
			var childInput = Std.downcast(childElement, Type.getClass(input));

			if (childInput != null) {
				childInput.value = input.value;
				childInput.onValueChange(isTemporaryEdit);
			}
		}

		if (!isTemporaryEdit) {
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
				}));
			}
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