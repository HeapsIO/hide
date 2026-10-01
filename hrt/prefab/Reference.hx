package hrt.prefab;

enum EditMode {
	/** The reference can't be edited in the editor **/
	None;

	/** The reference can be edited in the editor, and saving it will update the referenced prefab file on disk **/
	Edit;

	/** The reference can be edited, and saving it will save a diff between the original prefab and this in the `overrides` field **/
	Override;
}

typedef LoadedReference = {
	prefab: Prefab,
	version: Int,
	#if (editor || editor_hl)
	?originalSource: Dynamic,
	#end
};

@:prefabIcon(HuiRes.ui.icons.prefab.reference)
class Reference extends Object3D {
	/**
		The referenced prefab loaded by this reference
	**/
	public var refInstance(default, null) : Prefab;
	var refInstanceVersion : Int = -1;

	/**
		How the reference can be edited in the editor
	**/
	@:s public var editMode : EditMode = None;

	/**
		Holds the original override to apply when loading a reference from disk
	**/
	public var overrides : Dynamic = null;

	#if (editor || editor_hl)
	/**
		Copy of the original data to use as a reference on save for overrides
	**/
	public var originalSource : Dynamic;

	var wasMade : Bool = false;
	var firstLoaded : Bool = false;
	#end

	override function save() {
		var obj : Dynamic = super.save();

		#if (editor || editor_hl)
		if (editMode == Override) {
			// don't loose overrides if refInstance failed to load
			if (refInstance == null) {
				obj.overrides = overrides;
			} else {
				var diff = computeDiffFromSource();
				if (diff != null)
					obj.overrides = diff;
			}
		}
		#end

		#if editor
		if( editMode == Edit && refInstance != null ) {
			var sheditor = Std.downcast(shared, hide.prefab.ContextShared);
			if( sheditor.editor != null ) sheditor.editor.watchIgnoreChanges(source);

			var s = refInstance.serialize();
			sys.io.File.saveContent(hide.Ide.inst.getPath(source), hide.Ide.inst.toJSON(s));
		}
		#end

		return obj;
	}

	override function load(obj: Dynamic) {
		// Backward compatibility between old bool editMode and new enum based editMode
		if (Type.typeof(obj.editMode) == TBool) {
			obj.editMode = "Edit";
		}

		super.load(obj);

		#if (editor || editor_hl)
		if (!firstLoaded)
		#end
			overrides = obj.overrides;

		// References with overrides are always in Override mode
		if (overrides != null) {
			editMode = Override;
		}

		#if (editor || editor_hl)
		// Don't load a source that is already being loaded by one of our parents, to avoid infinite loops on cyclic references
		if (!firstLoaded && isSourceInParents()) {
			firstLoaded = true;
			return;
		}
		#end

		#if !(editor ||editor_hl)
		if (source != null && shouldBeInstanciated() && hxd.res.Loader.currentInstance?.exists(source)) {
			initRefInstance();
		}
		#else

		// Only set the refInstance if it's the initial editor load, otherwise refInstance must stay
		// as either null or the already loaded refInstance
		if (!firstLoaded) {
			setRefInstance(loadReference(source, editMode, overrides));
			firstLoaded = true;
		}
		#end
	}

	#if (editor || editor_hl)
	/** Returns true if source is the file of this reference or of one of its parents **/
	function isSourceInParents() : Bool {
		var p : Prefab = this;
		while (p != null) {
			if (p.shared.currentPath == source)
				return true;
			p = p.shared.parentPrefab;
		}
		return false;
	}

	/**
		Set the source of a newly created reference and load its refInstance.
		Must only be used when creating a Reference, not to modify it after the fact : changes
		to an existing reference source must go through the inspector so they can be undone.
		Throws if the refInstance is already loaded.
	**/
	public function editorInit(source: String) {
		if (refInstance != null)
			throw 'editorInit called on ${getAbsPath()} which already has a refInstance';

		this.source = source;
		firstLoaded = true;
		if (!isSourceInParents())
			setRefInstance(loadReference(source, editMode, overrides));
	}
	#end

	override function copy(obj: Prefab) {
		super.copy(obj);
		var otherRef : Reference = cast obj;

		#if (editor || editor_hl)
		originalSource = otherRef.originalSource;
		firstLoaded = otherRef.firstLoaded;
		#end

		overrides = otherRef.overrides;

		// Clone the refInstance from the original prefab on copy
		if (source != null && shouldBeInstanciated()) {
			#if !(editor || editor_hl)
			// Reload from scratch the refInstance if the disk version is more recent
			var newVersion = try hxd.res.Loader.currentInstance.load(source).toPrefab().reloadedVersion catch(e) -1;
			if (newVersion != otherRef.refInstanceVersion) {
				otherRef.refInstance = null;
				otherRef.initRefInstance();
			}
			#end

			if (otherRef.refInstance != null) {
				refInstance = otherRef.refInstance.clone(new ContextShared(source, null, null, true));
			}
			if (refInstance != null) {
				refInstance.shared.parentPrefab = this;
			}
		}
	}

	#if (editor || editor_hl)
	override function shouldBeInstanciated() {
		if (!super.shouldBeInstanciated())
			return false;

		// Avoid infinite loops with editor only prefabs
		if (editorOnly && shared.parentPrefab != null)
			return false;

		return true;
	}
	#end

	function computeDiffFromSource() : Dynamic {
		#if (editor || editor_hl)
		var orig = originalSource;
		var ref = refInstance?.serialize() ?? null;
		var diff = hrt.prefab.Diff.diffPrefab(orig, ref);
		switch (diff) {
			case Skip:
				return null;
			case Set(v):
				return hrt.prefab.Diff.deepCopy(v);
		}
		#else
		return null;
		#end
	}

	/**
		Loads the refInstance if it need to be init for the make process
	**/
	function initRefInstance() {
		#if !(editor || editor_hl)
		if (!shouldBeInstanciated())
			return;
		#end

		resolve();
	}

	@:deprecated("Use resolve() instead")
	inline function resolveRef() : Prefab {
		return resolve();
	}

	/**
		Try to resolve refInstance if it's not loaded.
		Loads the prefab referenced by `source`, apply overrides to it if applicable and store it in refInstance and returns it.
		If the prefab load process fails, refInstance is null
	**/
	public function resolve() : Prefab {
		#if (editor || editor_hl)
		// never try to load refInstance automatically if it's null in editor
		return refInstance;
		#end

		if (source == null)
			return null;

		if (refInstance != null)
			return refInstance;

		setRefInstance(loadReference(source, editMode, overrides));

		return refInstance;
	}

	public function loadReference(source: String, editMode: EditMode, overrides: Dynamic) : LoadedReference {
		#if (editor || editor_hl)
		try {
		#end
			// Don't load editorOnly references if we are already inside a reference
			// to avoid cyclic loops
			if (shared.parentPrefab != null && editorOnly)
				return null;

			var res = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab();
			var loaded : LoadedReference = { prefab: null, version: res.reloadedVersion };

			// parentPrefab must be set before the prefab is created, so the references inside it can detect cycles while loading
			var sh = new ContextShared(source, null, null, true);
			sh.parentPrefab = this;

			#if (editor || editor_hl)
			// Keep the original data in editable modes, so overrides can be computed when moving between Edit and Override mode
			// (moving from or to None always reloads the reference)
			if (editMode != None)
				loaded.originalSource = @:privateAccess res.loadData();

			// Don't use the cached prefab in editor, as it can't have a parentPrefab
			var refInstanceData = @:privateAccess res.loadData();
			if (overrides != null) {
				// Diff.apply takes ownership of the diff, and the refInstance can be resolved again multiple times
				// so we need to keep overrides intact
				refInstanceData = hrt.prefab.Diff.apply(refInstanceData, hrt.prefab.Diff.deepCopy(overrides));
			}
			loaded.prefab = hrt.prefab.Prefab.createFromDynamic(refInstanceData, null, sh);
			#else
			if (overrides != null) {
				var refInstanceData = @:privateAccess res.loadData();

				// Diff.apply takes ownership of the diff, and the refInstance can be resolved again multiple times
				// (e.g. when copy() reloads a newer version from disk), so we need to keep overrides intact
				refInstanceData = hrt.prefab.Diff.apply(refInstanceData, hrt.prefab.Diff.deepCopy(overrides));
				loaded.prefab = hrt.prefab.Prefab.createFromDynamic(refInstanceData, null, sh);
			} else {
				// Don't clone the refInstance if we are the original prefab
				// Temp disabled until we figure out how to manage how to handle the prefab api that uses followRef on cached prefabs
				loaded.prefab = res.load().clone();
			}
			#end

			return loaded;
		#if (editor || editor_hl)
		} catch (e) {
			return null;
		}
		#end
	}

	/**
		Replace the refInstance of this reference with `loaded`, removing the objects of the previous refInstance.
		Must only be called while loading the reference or inside an undo/redo step
	**/
	function setRefInstance(loaded: LoadedReference) {
		refInstance?.editorRemoveObjects();

		refInstance = loaded?.prefab;
		refInstanceVersion = loaded?.version ?? -1;
		#if (editor || editor_hl)
		originalSource = loaded?.originalSource;
		#end

		if (refInstance != null)
			refInstance.shared.parentPrefab = this;
	}

	/**
		Return the current refInstance state of this reference, to be restored later with setRefInstance
	**/
	public function saveRefInstance() : LoadedReference {
		var saved : LoadedReference = { prefab: refInstance, version: refInstanceVersion };
		#if (editor || editor_hl)
		saved.originalSource = originalSource;
		#end
		return saved;
	}

	override function makeInstance() {
		if( source == null )
			return;

		#if editor_hl
		if (!hxd.res.Loader.currentInstance.exists(source)) {
			throw 'Source prefab `${source}` does not exist';
			return;
		}

		// refInstance is only loaded with the reference, a null refInstance means the reference is broken (cycle or load error)
		if (refInstance == null) {
			throw 'Source prefab `${source}` couldn\'t be loaded or creates a reference cycle';
			return;
		}
		#end

		// Retro compatibility for references created in code, where source is set after the reference was created
		initRefInstance();

		#if (editor || editor_hl)
		// The refInstance is kept between makes in Edit/Override mode, the editor must remove its objects before remaking it
		if (wasMade && refInstance != null)
			throw 'Reference ${getAbsPath()} is made again but its refInstance objects were not removed by the editor';
		#end

		var refLocal3d : h3d.scene.Object = null;

		if (Std.downcast(refInstance, Object3D) != null) {
			refLocal3d = shared.current3d;
		} else {
			super.makeInstance();
			refLocal3d = local3d;
		}

		if (refInstance == null) {
			return;
		}

		var sh = refInstance.shared;
		@:privateAccess sh.root3d = sh.current3d = refLocal3d;
		@:privateAccess sh.root2d = sh.current2d = findFirstLocal2d();

		#if editor
		sh.editor = this.shared.editor;
		sh.scene = this.shared.scene;
		if (sh.isInstance == false)
			throw "isInstance should be true";
		#end
		sh.parentPrefab = this;
		sh.customMake = this.shared.customMake;

		if (refInstance.to(Object3D) != null) {
			var obj3d = refInstance.to(Object3D);
			obj3d.loadTransform(this); // apply this transform to the reference prefab
			obj3d.name = name;
			obj3d.visible = visible;
			refInstance.make();
			local3d = Object3D.getLocal3d(refInstance);
		}
		else {
			refInstance.make();
		}

		#if (editor || editor_hl)
		wasMade = true;
		#end
	}

	#if (editor || editor_hl)
	override public function editorRemoveObjects() : Void {
		if (refInstance != null)
			refInstance.editorRemoveObjects();
		wasMade = false;
		super.editorRemoveObjects();
	}

	override public function onEditorTreeChanged(prefab: Prefab) : hrt.prefab.Prefab.TreeChangedResult {
		if (prefab == refInstance)
			return Rebuild;
		return super.onEditorTreeChanged(prefab);
	}
	#end

	override public function findRec<T:Prefab>(?cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false, includeDisabled: Bool = true) : Null<T> {
		if (!includeDisabled && !enabled)
			return null;
		var res = super.findRec(cl, filter, followRefs, includeDisabled);
		if (res == null && followRefs ) {
			var p = resolve();
			if( p != null )
				return p.findRec(cl, filter, followRefs, includeDisabled);
		}
		return res;
	}

	override public function getOpt<T:Prefab>( ?cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
		var res = super.getOpt(cl, name, followRefs);
		if (res == null && followRefs && resolve() != null) {
			return refInstance.getOpt(cl, name, followRefs);
		}
		return res;
	}

	override public function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T>) : Array<T> {
		arr = super.flatten(cl, arr);
		if (editMode != None && resolve() != null) {
			arr = refInstance.flatten(cl, arr);
		}
		return arr;
	}

	override function dispose() {
		super.dispose();
		if( refInstance != null )
			refInstance.dispose();
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {

		ctx.build(
			<category("Reference")>
				<file type="prefab" field={source} id="fileSource" no-undo/>
				<select field={editMode} id="editModeSelect" no-undo default-value={None}/>
				<text("Warning : This reference loading failed") if(refInstance == null)/>
			</category>
		);

		@:privateAccess fileSource.onFieldChange = (_) -> {

			var oldSource = source;
			var newSource = fileSource.value;

			var oldName = this.name;
			var newName = this.name;
			if(oldName == new haxe.io.Path(oldSource).file){
				newName = new haxe.io.Path(newSource).file;
			}

			var oldRef = saveRefInstance();
			var newRef = loadReference(newSource, editMode, null);

			if (newRef == null && newSource != null) {
				ctx.quickError('Couldn\'t load $newSource, source is not changed');
				ctx.rebuildInspector();
				return;
			}

			if (newRef != null && checkCycle(this, newRef.prefab)) {
				ctx.quickError('Couldn\'t load $newSource, this create a reference cycle');
				ctx.rebuildInspector();
				return;
			}

			function exec(isUndo) {
				if (oldName != newName) {
					this.name = isUndo ? oldName : newName;
					ctx.rebuildTree(this);
				}
				source = isUndo ? oldSource : newSource;
				setRefInstance(isUndo ? oldRef : newRef);
				ctx.rebuildPrefab(this);
				ctx.rebuildInspector();
			};
			exec(false);
			ctx.recordUndo(exec);
		}

		@:privateAccess editModeSelect.onFieldChange = (_) -> {
			var oldRef = saveRefInstance();
			var oldEditMode = editMode;
			var newEditMode = editModeSelect.value;

			var overrides = null;
			var newRef = oldRef;
			// Keep overrides if we move between Edit mode and Override Mode
			if (oldEditMode  == None || newEditMode == None)
				newRef = loadReference(source, newEditMode, null);

			// Todo : when moving to None, alert user that changes / overrides will be lost
			// but we need an api in ctx to prompt the user for a choice

			if (newRef == null && source != null) {
				ctx.quickError('Couldn\'t load $source from disk, aborting edit mode changes');
				ctx.rebuildInspector();
				return;
			}

			function exec(isUndo) {
				editMode = isUndo ? oldEditMode : newEditMode;
				setRefInstance(isUndo ? oldRef : newRef);
				ctx.rebuildPrefab(this);
				ctx.rebuildTree(this);
				ctx.rebuildInspector();
			};
			exec(false);
			ctx.recordUndo(exec);
		}

		super.edit2(ctx);

		if (editMode == Override) {
			var hasOverrides = computeDiffFromSource() != null;

			ctx.build(
				<category("Overrides")>
					<text(hasOverrides ? "This reference has overrides" : "No Overrides")/>
					<button("Clear Overrides") id="btnClearOverrides" disabled={!hasOverrides}/>
				</category>
			);

			// The kit undo only saves/loads the reference data, which doesn't restore the refInstance, so we record our own undo
			btnClearOverrides.noUndo = true;
			btnClearOverrides.onClick = () -> {
				var oldRef = saveRefInstance();
				var oldOverrides = overrides;
				var newRef = loadReference(source, editMode, null);

				if (newRef == null && source != null) {
					ctx.quickError('Couldn\'t reload $source from disk, aborting override changes');
					ctx.rebuildInspector();
					return;
				}

				function exec(isUndo: Bool) {
					setRefInstance(isUndo ? oldRef : newRef);
					overrides = isUndo ? oldOverrides : null;
					ctx.rebuildPrefab(this);
					ctx.rebuildInspector();
				}
				exec(false);
				ctx.recordUndo(exec);
			};
		}

	}

	override function makeInteractive() {
		if( editMode != None )
			return null;
		return super.makeInteractive();
	}

	/**
		Returns true if `reference` would have a cycle if `refPrefab` was its refInstance
	**/
	public static function checkCycle(reference: Reference, refPrefab: Prefab) : Bool {

		function rec(prefab: Prefab, seenPaths: Map<String, Bool>) : Bool {
			if (prefab == null)
				return false;

			var ref = Std.downcast(prefab, Reference);
			if (ref != null && ref.source != null && ref.shouldBeInstanciated() && !ref.editorOnly) {
				// the checked reference uses refPrefab instead of its own refInstance
				var inst = ref == reference ? refPrefab : ref.resolve();
				var path = ref == reference ? (refPrefab?.shared.currentPath ?? ref.source) : ref.source;
				if (seenPaths.get(path) == true) {
					return true;
				}

				var copy = seenPaths.copy();
				copy.set(path, true);
				if (rec(inst, copy))
					return true;
			}
			for (child in prefab.children) {
				if(rec(child, seenPaths))
					return true;
			}

			return false;
		}

		var baseMap = new Map();
		if (reference.shared.currentPath != null) {
			baseMap.set(reference.shared.currentPath, true);
		}
		return rec(reference, baseMap);
	}


	#if editor

	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor, scene: hide.comp.Scene) {
		super.setEditorChildren(sceneEditor, scene);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor, scene);
		}
	}

	/**
		Updates the original reference data to be equal to `data`.
		If the ref is an override, the override will be kept as is
	**/
	function setRef(data: Dynamic) {
		if (data == null)
			throw "Null data";

		if (refInstance == null)
			return;

		var currentSerialization = refInstance.serialize();
		var pristineData = hrt.prefab.Diff.deepCopy(data);

		// we might have unsaved changes
		if (editMode == Override) {
			switch(hrt.prefab.Diff.diffPrefab(originalSource, currentSerialization)) {
				case Skip:
				case Set(diff):
					pristineData = hrt.prefab.Diff.apply(pristineData, diff);
			}
		}
		else if (overrides != null) {
			pristineData = hrt.prefab.Diff.apply(pristineData, hrt.prefab.Diff.deepCopy(overrides));
		}

		originalSource = hrt.prefab.Diff.deepCopy(data);

		refInstance = Prefab.createFromDynamic(pristineData, new ContextShared(source, true));
		refInstance.shared.parentPrefab = this;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "share", name : "Reference" };
	}

	@:access(hide.comp.SceneEditor)
	static function breakReferences(selectedRefs : Array<Reference>) : Void {
		var editor = selectedRefs[0].shared.editor;

		var clones : Array<hrt.prefab.Prefab> = [];
		var parents : Array<hrt.prefab.Prefab> = [];

		for (selectedRef in selectedRefs) {
			var root = new hrt.prefab.Object3D(null, selectedRef.shared);
			for (child in selectedRef.resolve().children) {
				child.clone(root);
			}
			root.name = selectedRef.name;
			root.visible = selectedRef.visible;
			root.loadTransform(selectedRef.saveTransform());

			clones.push(root);
			parents.push(selectedRef.parent);
		}

		function exec(isUndo) {
			editor.beginRebuild();

			var newSelection : Array<hrt.prefab.Prefab> = [];
			for (i => selectedRef in selectedRefs) {
				if (!isUndo) {

					// find our prefab in the parent children,
					// and swap it with the clone
					for (childIndex => prefab in parents[i].children) {
						if (prefab != selectedRef) continue;
						parents[i].removeChild(parents[i].children[i]);
						parents[i].addChildAt(clones[i], childIndex);
						break;
					}
					editor.removeInstance(selectedRef, false);
					selectedRef.remove();
					newSelection.push(clones[i]);
				}
				else {
					// find our clone in the parent children,
					// and swap it with the original prefab
					for (childIndex => prefab in parents[i].children) {
						if (prefab != clones[i]) continue;
						parents[i].removeChild(parents[i].children[i]);
						parents[i].addChildAt(selectedRef, childIndex);
						break;
					}
					editor.removeInstance(clones[i], false);
					clones[i].remove();
					newSelection.push(selectedRef);
				}
				editor.queueRebuild(parents[i]);
			}

			editor.endRebuild();

			editor.selectElements(newSelection, Nothing);
			editor.refreshTree(All);
		}

		exec(false);
		editor.view.undo.change(Custom(exec));
	}

	static function onContextMenu(selection: Array<hrt.prefab.Prefab>) : Array<hrt.ui.HuiMenu.MenuItem> {
		return [{
			label: "Break References",
			click: () -> {
				breakReferences(cast selection);
			},
		}];
	}

	public static var _1 =  hide.comp.SceneEditor.registerContextMenuExtension(Reference, onContextMenu);
	#end


	public static var _ = hrt.prefab.Prefab.register("reference", Reference);
}