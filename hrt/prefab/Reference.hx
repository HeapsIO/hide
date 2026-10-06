package hrt.prefab;

enum EditMode {
	/** The reference can't be edited in the editor **/
	None;

	/** The reference can be edited in the editor, and saving it will update the referenced prefab file on disk **/
	Edit;

	/** The reference can be edited, and saving it will save a diff between the original prefab and this in the `overrides` field **/
	Override;
}

/** A null prefab means the reference failed to load **/
typedef LoadedReference = {
	prefab: Prefab,
	version: Int,
	#if (editor || editor_hl)
	originalSource: Dynamic,
	/** True if the loaded source, or a reference inside it, creates a reference cycle **/
	hasCycle: Bool,
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
	var originalSource : Dynamic;

	/**
		True if this reference, or a reference inside its refInstance, creates a reference cycle.
		The reference closing the cycle has a null refInstance.
	**/
	public var hasCycle(default, null) : Bool = false;

	var wasMade : Bool = false;
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

		// hide_hl saves the Edit mode references itself in its save process
		#if editor
		if( !shared.isTempSave() && editMode == Edit && refInstance != null ) {
			var sheditor = Std.downcast(shared, hide.prefab.ContextShared);
			if( sheditor.editor != null ) sheditor.editor.watchIgnoreChanges(source);

			var s = refInstance.serialize();
			sys.io.File.saveContent(hide.Ide.inst.getPath(source), hide.Ide.inst.toJSON(s));
		}
		#end

		#end

		return obj;
	}

	override function load(obj: Dynamic) {
		// Backward compatibility between old bool editMode and new enum based editMode
		if (Type.typeof(obj.editMode) == TBool) {
			obj.editMode = "Edit";
		}

		super.load(obj);

		#if !(editor ||editor_hl)
		if (source != null && hxd.res.Loader.currentInstance?.exists(source)) {
			initRefInstance();
		}
		#else

		// Only set the refInstance if it's the initial editor load, otherwise refInstance must stay
		// as either null or the already loaded refInstance
		if (!shared.isTempLoad()) {
			// References with overrides in their file are always in Override mode. Temporary loads (like undo/redo) keep
			// the overrides and edit mode handled by the editor
			overrides = obj.overrides;
			if (overrides != null)
				editMode = Override;

			resolveInternal();
		}
		#end
	}

	#if (editor || editor_hl)
	static function containsCycle(prefab: Prefab) : Bool {
		return prefab?.findRec(Reference, (r) -> r.hasCycle) != null;
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
		resolveInternal();
	}
	#end

	override function copy(obj: Prefab) {
		super.copy(obj);
		var otherRef : Reference = cast obj;

		#if (editor || editor_hl)
		originalSource = otherRef.originalSource;
		hasCycle = otherRef.hasCycle;
		#end

		overrides = otherRef.overrides;

		// Clone the refInstance from the original prefab on copy
		if (source != null && shouldBeInstanciated()) {
			#if !(editor || editor_hl || release)
			// Reload from scratch the refInstance if the disk version is more recent
			var loader = hxd.res.Loader.currentInstance;
			if (Std.isOfType(loader.fs, hxd.fs.LocalFileSystem)) {
				var newVersion = try loader.load(source).toPrefab().reloadedVersion catch(e) -1;
				if (newVersion != otherRef.refInstanceVersion) {
					otherRef.refInstance = null;
					otherRef.initRefInstance();
				}
			}
			#end

			if (otherRef.refInstance != null) {
				refInstanceVersion = otherRef.refInstanceVersion;
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

	#if !(editor || editor_hl)
	/**
		Loads the refInstance if it need to be init for the make process
	**/
	function initRefInstance() {
		if (!shouldBeInstanciated())
			return;

		resolve();
	}
	#end

	/**
		Try to resolve refInstance if it's not loaded.
		Loads the prefab referenced by `source`, apply overrides to it if applicable and store it in refInstance and returns it.
		If the prefab load process fails, refInstance is null
	**/
	public function resolve() : Prefab {
		#if (editor || editor_hl)
		// never try to load refInstance automatically if it's null in editor
		return refInstance;
		#else
		if (source == null)
			return null;

		if (refInstance != null)
			return refInstance;

		resolveInternal();

		return refInstance;
		#end
	}

	/**
		Loads the prefab referenced by `source` with this reference editMode and overrides, and replace refInstance with it
	**/
	function resolveInternal() : Void {
		inline applyLoadedReference(inline loadReference(source, editMode, overrides));
	}

	function loadReference(source: String, editMode: EditMode, overrides: Dynamic) : LoadedReference {
		// Single struct declaration and single return, so it can be inlined in resolveInternal
		var loaded : LoadedReference = { #if (editor || editor_hl) originalSource: null, hasCycle: false, #end prefab: null, version: -1 };
		#if (editor || editor_hl)
		try {
		#end
			// Don't load editorOnly references if we are already inside a reference
			// to avoid cyclic loops
			var canLoad = shared.parentPrefab == null || !editorOnly;

			#if (editor || editor_hl)
			// Don't load a source that is already being loaded by one of our parents, to avoid infinite loops on cyclic references
			var p : Prefab = this;
			while (canLoad && source != null && p != null) {
				if (p.shared.currentPath == source) {
					loaded.hasCycle = true;
					canLoad = false;
				}
				p = p.shared.parentPrefab;
			}
			#end

			if (canLoad) {
				var res = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab();
				loaded.version = res.reloadedVersion;

				// parentPrefab must be set before the prefab is created, so the references inside it can detect cycles while loading
				var sh = new ContextShared(source, null, null, true);
				sh.parentPrefab = this;

				#if (editor || editor_hl)
				// Keep the original data in editable modes, so overrides can be computed when moving between Edit and Override mode
				// (moving from or to None always reloads the reference)
				if (editMode != None)
					loaded.originalSource = @:privateAccess res.loadData();

				// Don't use the cached prefab in editor, as it can't have a parentPrefab
				var useData = true;
				#else
				var useData = overrides != null;
				#end

				if (useData) {
					var refInstanceData = @:privateAccess res.loadData();
					if (overrides != null) {
						// Diff.apply takes ownership of the diff, and the refInstance can be resolved again multiple times
						// (e.g. when copy() reloads a newer version from disk), so we need to keep overrides intact
						refInstanceData = hrt.prefab.Diff.apply(refInstanceData, hrt.prefab.Diff.deepCopy(overrides));
					}
					loaded.prefab = hrt.prefab.Prefab.createFromDynamic(refInstanceData, null, sh);
				} else {
					// Don't clone the refInstance if we are the original prefab
					// Temp disabled until we figure out how to manage how to handle the prefab api that uses followRef on cached prefabs
					loaded.prefab = res.load().clone();
				}

				#if (editor || editor_hl)
				loaded.hasCycle = containsCycle(loaded.prefab);
				#end
			}
		#if (editor || editor_hl)
		} catch (e) {
			loaded.prefab = null;
			loaded.originalSource = null;
		}
		#end
		return loaded;
	}

	/**
		Replace the refInstance of this reference with `loaded`, removing the objects of the previous refInstance.
		Must only be called while loading the reference or inside an undo/redo step
	**/
	function applyLoadedReference(loaded: LoadedReference) {
		refInstance?.editorRemoveObjects();

		refInstance = loaded.prefab;
		refInstanceVersion = loaded.version;
		#if (editor || editor_hl)
		originalSource = loaded.originalSource;
		hasCycle = loaded.hasCycle;
		#end

		if (refInstance != null)
			refInstance.shared.parentPrefab = this;
	}

	/**
		Return the current refInstance state of this reference, to be restored later with applyLoadedReference
	**/
	function getLoadedReference() : LoadedReference {
		return { #if (editor || editor_hl) originalSource: originalSource, hasCycle: hasCycle, #end prefab: refInstance, version: refInstanceVersion };
	}

	#if (editor || editor_hl)
	/**
		Returns an undo action that replaces the refInstance with a copy of `sourceInstance`, the edited content of
		the same source file (from another reference in Edit mode). In Override mode, the overrides of this reference are kept.
		Must be recorded in an undo/redo step.
	**/
	public function editorSyncSourceAction(sourceInstance: Prefab) : (isUndo: Bool) -> Void {
		var oldRef = getLoadedReference();

		var sh = new ContextShared(source, null, null, true);
		sh.parentPrefab = this;

		var newRef : LoadedReference = { originalSource: null, hasCycle: false, prefab: null, version: refInstanceVersion };
		// serialize() shares untyped fields (like `props`) with sourceInstance, deep copy them so
		// edits of sourceInstance don't leak into our originalSource and refInstance
		// the edited content will be the content of the file once saved
		var serializedData = sourceInstance.serialize();
		if (editMode != None)
			newRef.originalSource = hrt.prefab.Diff.deepCopy(serializedData);

		var data : Dynamic = hrt.prefab.Diff.deepCopy(serializedData);
		var localOverrides = editMode == Override ? computeDiffFromSource() : null;
		if (localOverrides != null)
			data = hrt.prefab.Diff.apply(data, localOverrides);
		newRef.prefab = Prefab.createFromDynamic(data, null, sh);
		newRef.hasCycle = containsCycle(newRef.prefab);

		return (isUndo) -> applyLoadedReference(isUndo ? oldRef : newRef);
	}
	#end

	override function makeInstance() {
		if( source == null )
			return;

		#if editor_hl
		if (!hxd.res.Loader.currentInstance.exists(source)) {
			throw 'Source prefab `${source}` does not exist';
		}

		// refInstance is only loaded with the reference, a null refInstance means the reference is broken (cycle or load error)
		if (refInstance == null) {
			throw 'Source prefab `${source}` couldn\'t be loaded or creates a reference cycle';
		}
		#end

		#if !(editor || editor_hl)
		// Retro compatibility for references created in code, where source is set after the reference was created
		initRefInstance();
		#end

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
				<text("Warning : This reference loading failed") if(refInstance == null && !ctx.root.isMultiEdit)/>
			</category>
		);

		// Shows an error and returns true if `newRef` failed to load `source` or creates a reference cycle
		function checkRefErrors(newRef: LoadedReference, source: String, message: String) : Bool {
			var hasCycle = #if (editor || editor_hl) newRef.hasCycle #else false #end;
			if (!hasCycle && (newRef.prefab != null || source == null))
				return false;
			ctx.quickError(hasCycle ? 'Couldn\'t load $source, this create a reference cycle' : message);
			ctx.rebuildInspector();
			return true;
		}

		@:privateAccess fileSource.onFieldChange = (_) -> {

			var oldSource = source;
			var newSource = fileSource.value;

			var oldName = this.name;
			var newName = this.name;
			if(oldName == new haxe.io.Path(oldSource).file){
				newName = new haxe.io.Path(newSource).file;
			}

			var oldRef = getLoadedReference();
			var newRef = loadReference(newSource, editMode, null);

			// Todo : prompt the user that changing the source will loose the edits/overrides in place

			if (checkRefErrors(newRef, newSource, 'Couldn\'t load $newSource, source is not changed'))
				return;

			function exec(isUndo) {
				if (oldName != newName) {
					this.name = isUndo ? oldName : newName;
					ctx.rebuildTree(this);
				}
				source = isUndo ? oldSource : newSource;
				applyLoadedReference(isUndo ? oldRef : newRef);
				ctx.rebuildPrefab(this);
				ctx.rebuildInspector();
			};
			exec(false);
			ctx.recordUndo(exec, [this]);
		}

		@:privateAccess editModeSelect.onFieldChange = (_) -> {
			var oldRef = getLoadedReference();
			var oldEditMode = editMode;
			var newEditMode = editModeSelect.value;

			var oldOverrides = overrides;
			// Overrides are lost when moving to None mode
			var newOverrides = newEditMode == None ? null : overrides;
			var newRef = oldRef;
			// Keep overrides if we move between Edit mode and Override Mode
			if (oldEditMode  == None || newEditMode == None)
				newRef = loadReference(source, newEditMode, null);

			// Todo : when moving to None, alert user that changes / overrides will be lost
			// but we need an api in ctx to prompt the user for a choice

			if (newRef != oldRef && checkRefErrors(newRef, source, 'Couldn\'t load $source from disk, aborting edit mode changes'))
				return;

			function exec(isUndo) {
				editMode = isUndo ? oldEditMode : newEditMode;
				overrides = isUndo ? oldOverrides : newOverrides;
				applyLoadedReference(isUndo ? oldRef : newRef);
				ctx.rebuildPrefab(this);
				ctx.rebuildTree(this);
				ctx.rebuildInspector();
			};
			exec(false);
			ctx.recordUndo(exec, [this]);
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
				var oldRef = getLoadedReference();
				var oldOverrides = overrides;
				var newRef = loadReference(source, editMode, null);

				if (checkRefErrors(newRef, source, 'Couldn\'t reload $source from disk, aborting override changes'))
					return;

				function exec(isUndo: Bool) {
					applyLoadedReference(isUndo ? oldRef : newRef);
					overrides = isUndo ? oldOverrides : null;
					ctx.rebuildPrefab(this);
					ctx.rebuildInspector();
				}
				exec(false);
				ctx.recordUndo(exec, [this]);
			};
		}

	}

	override function makeInteractive() {
		if( editMode != None )
			return null;
		return super.makeInteractive();
	}

	#if editor

	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor, scene: hide.comp.Scene) {
		super.setEditorChildren(sceneEditor, scene);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor, scene);
		}
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