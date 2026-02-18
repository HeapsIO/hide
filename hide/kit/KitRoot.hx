package hide.kit;

#if domkit

class KitRoot #if !macro extends Element #end {
	#if !macro
	public var editedPrefabsProperties : Array<KitRoot> = [];
	var prefab : hrt.prefab.Prefab;
	var prefabUndoPoint : Dynamic = null;
	public var editor(default, null) : hrt.prefab.EditContext2;
	public var isMultiEdit(default, null) : Bool;

	public function new(parent: Element, id: String, prefab: hrt.prefab.Prefab, editor: hrt.prefab.EditContext2) {
		super(parent, id);
		this.prefab = prefab;
		this.editor = editor;
		root = root ?? this;
	}

	override function makeSelf() : Void {
		#if js
		native = js.Browser.document.createElement("kit-root");

		var title = js.Browser.document.createElement("kit-title");
		var titleText = prefab.getHideProps().name;
		if (editedPrefabsProperties.length > 1)
			titleText += ' (${editedPrefabsProperties.length})';
		title.textContent = titleText;
		native.addChild(title);

		var toolbar = js.Browser.document.createElement("kit-toolbar");
		native.addChild(toolbar);
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


		#elseif hui
		native = new hrt.ui.HuiElement();
		native.get().dom.setId("root");
		#end
	}

	public function getElementByPath(path: String) {
		var parts = path.split(".");
		var currentElement : Element = this;
		for (part in parts) {
			currentElement = currentElement.getChildById(part);
			if (currentElement == null)
				break;
		}
		return currentElement;
	}

	override function change(callback: () -> Void, isTemporaryEdit: Bool) : Void {
		prepareUndoPoint();

		callback();

		if (!isTemporaryEdit) {
			finishUndoPoint();
		}
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
				editor.rebuildInspector();
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

	public function postEditStep() {
		if (prefab != null) {
			new CDB(this, "cdb");
		}
	}

	#end
}

#end