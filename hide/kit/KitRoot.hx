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

	/**
		Execute the given callback. Allows editors to try to throw in the cb in a graceful manner
	**/
	public dynamic function doTry(cb: Void -> Void) {
		cb();
	}

	override function change(params: hide.kit.Element.ChangeParams) : Void {
		// merge the undo steps recorded by all the edited prefabs (in multi edit) in a single step
		editor.beginMultiUndo();

		if (params.recordUndo) {
			prepareUndoPoint();
		}

		params.callback();
		if (params.sideEffects != null)
			params.sideEffects(false);

		if (!params.isTemporaryEdit && params.recordUndo) {
			finishUndoPoint(params.sideEffects);
		}

		editor.finishMultiUndo();
	}

	/**
		Creates an undoPoint for the currently edited prefabs if none exists
	**/
	function prepareUndoPoint() : Void {
		if (prefabUndoPoint == null) {
			editor.resetRebuilds();
			prefabUndoPoint = hrt.prefab.Diff.deepCopy(prefab.save());
			for (childProperties in editedPrefabsProperties) {
				childProperties.editor.resetRebuilds();
				childProperties.prefabUndoPoint = hrt.prefab.Diff.deepCopy(childProperties.prefab.save());
			}
		}
	}

	function finishUndoPoint(?customSideEffect: (isUndo: Bool) -> Void) {
		// no change was recorded since the last finishUndoPoint
		if (prefabUndoPoint == null)
			return;

		var sideEffects : Array<(isUndo:Bool) -> Void> = [];
		createUndoStep(sideEffects);

		for (childProperties in editedPrefabsProperties) {
			childProperties.createUndoStep(sideEffects);
		}

		// in multi edit, the edited prefabs rebuild requests are tracked by their own edit context
		var treeRebuild = false;
		for (kit in [this].concat(editedPrefabsProperties)) {
			for (prefab in kit.editor.requestedPrefabRebuilds) {
				sideEffects.push((_) -> editor.rebuildPrefab(prefab));
			}
			treeRebuild = treeRebuild || kit.editor.requestedTreeRebuild;
		}

		if (treeRebuild) {
			sideEffects.push((_) -> editor.rebuildTree(null));
		}

		if (customSideEffect != null) {
			sideEffects.push(customSideEffect);
		}

		if (sideEffects.length > 0) {
			editor.recordUndo((isUndo: Bool) -> {
				for (sideEffect in sideEffects) {
					sideEffect(isUndo);
				}
				editor.rebuildInspector();
			}, getEditedPrefabs());
		}


	}

	function getEditedPrefabs() : Array<hrt.prefab.Prefab> {
		// in multi edit, the root prefab is a temporary copy, the edited prefabs are the child properties ones
		return editedPrefabsProperties.length > 0 ? [for (childProperties in editedPrefabsProperties) childProperties.prefab] : [prefab];
	}

	function createUndoStep(sideEffects : Array<(isUndo:Bool) -> Void>) : Void {
		var before = prefabUndoPoint;
		prefabUndoPoint = null;
		// save() and load() keep Dynamic fields (like `props`) by reference, copy them so later edits don't alter the undo snapshots
		var after = hrt.prefab.Diff.deepCopy(prefab.save());
		if (hrt.prefab.Diff.diff(before, after) != Skip) {
			sideEffects.push((isUndo) -> {
				var data = hrt.prefab.Diff.deepCopy(isUndo ? before : after);
				#if (editor || editor_hl)
				prefab.editorTempLoad(data);
				#else
				prefab.load(data);
				#end
				doTry(() -> prefab.updateInstance());
			});
		}
	}

	public function postEditStep() {
		#if castle
		if (prefab != null) {
			new CDB(this, "cdb");
		}
		#end
	}

	#end
}

#end