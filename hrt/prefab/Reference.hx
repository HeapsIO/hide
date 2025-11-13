package hrt.prefab;

enum EditMode {
	/** The reference can't be edited in the editor **/
	None;

	/** The reference can be edited in the editor, and saving it will update the referenced prefab file on disk **/
	Edit;

	/** The reference can be edited, and saving it will save a diff between the original prefab and this in the `overrides` field **/
	Override;
}
class Reference extends Object3D {
	/**
		The referenced prefab loaded by this reference
	**/
	public var refInstance : Prefab;
	var refInstanceVersion : Int = -1;

	/**
		How the reference can be edited in the editor
	**/
	@:s public var editMode : EditMode = None;

	/**
		List of all the properties that differs between this reference
		and the original prefab data. Use the format defined by
		hrt.prefab.Diff.diffPrefab
	**/
	@:s public var overrides : Dynamic = null;

	/**
		Copy of the original data to use as a reference on save for overrides
	**/
	public var originalSource : Dynamic;

	#if editor
	var wasMade : Bool = false;
	#end

	override function set_source(newSource:String):String {
		if (newSource != source) {
			resetRefInstance();
		}
		return source = newSource;
	}

	override function save() {
		#if editor
		if (editMode == Override && refInstance != null) {
			this.overrides = computeDiffFromSource();
		} else if (editMode == Edit && refInstance != null) {
			this.overrides = null;
		}
		#end

		var obj : Dynamic = super.save();

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

		#if !editor
		if (source != null && shouldBeInstanciated() && hxd.res.Loader.currentInstance.exists(source)) {
			initRefInstance();
		}
		#end

	}

	override function copy(obj: Prefab) {
		super.copy(obj);
		var otherRef : Reference = cast obj;

		#if editor
		try {
			originalSource = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab().loadData();
		} catch (e) {

		}
		#end

		// Clone the refInstance from the original prefab on copy
		if (source != null && shouldBeInstanciated()) {
			var newVersion = hxd.res.Loader.currentInstance.load(source).toPrefab().reloadedVersion;
			if (newVersion != otherRef.refInstanceVersion) {
				otherRef.refInstance = null;
				otherRef.initRefInstance();
			}

			if (otherRef.refInstance != null) {
				refInstance = otherRef.refInstance.clone(new ContextShared(source, null, null, true));
			}
			if (refInstance != null) {
				refInstance.shared.parentPrefab = this;
			}
		}
	}

	#if editor
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
		var orig = originalSource;
		var ref = refInstance?.serialize() ?? null;
		var diff = hrt.prefab.Diff.diffPrefab(orig, ref);
		switch (diff) {
			case Skip:
				return null;
			case Set(v):
				return hrt.prefab.Diff.deepCopy(v);
		}
	}

	function initRefInstance() {
		var shouldLoad = refInstance == null && source != null && shouldBeInstanciated();

		#if editor
		if (hasCycle())
			shouldLoad = false;
		#end

		if (shouldLoad) {
			resolve();
		}
	}

	/**
		Loads the prefab referenced by `source`, apply overrides to it if applicable and store it in refInstance and returns it.
	**/
	public function resolve() : Prefab {
		if (refInstance != null)
			return refInstance;

		if (shared.parentPrefab != null && editorOnly)
			return null;

		#if editor
		try {
		#end
			var res = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab();

			if (overrides != null) {
				var refInstanceData = @:privateAccess res.loadData();

				#if editor
				originalSource = @:privateAccess res.loadData();
				#end

				refInstanceData = hrt.prefab.Diff.apply(refInstanceData, overrides);
				refInstance = hrt.prefab.Prefab.createFromDynamic(refInstanceData, null, new ContextShared(source, null, null, true));
			} else {
				// Don't clone the refInstance if we are the original prefab
				if (!shared.isInstance && false /**Temp disabled until we figure out how to manage how to handle the prefab api that uses followRef on cached prefabs**/) {
					refInstance = res.load();
				} else {
					refInstance = res.load().clone();
				}
			}

			refInstanceVersion = res.reloadedVersion;

			refInstance.shared.parentPrefab = this;

		#if editor
		} catch (e) {
			return null;
		}
		#end

		return refInstance;
	}

	override function makeInstance() {
		if( source == null )
			return;


		// in the case source has changed since the last load (can happen when creating references manually)
		if (refInstance?.shared.currentPath != source) {
			initRefInstance();
			if (refInstance == null)
				return;
			refInstance = refInstance.clone();
		}
		#if editor
		if (hasCycle()) {
			hide.Ide.inst.quickError('Reference ${getAbsPath()} to $source is creating a cycle. Please fix the reference.');
			refInstance = null;
			return;
		}
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

		#if editor
		wasMade = true;
		#end
	}

	override function editorRemoveInstanceObjects() {
		super.editorRemoveInstanceObjects();
		// Clean cache to force proper ref reloading
		@:privateAccess if (source != null) {
			var cachedPrefab = Std.downcast(hxd.res.Loader.currentInstance.cache.get(source), hrt.prefab.Resource);
			if (cachedPrefab != null) {
				cachedPrefab.prefab = null;
			}
		}
		refInstance = null;
	}

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

	function resetRefInstance() {
		#if editor
		editorRemoveObjects();
		#end

		refInstance = null;
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {

		ctx.build(
			<category("Reference")>
				<file type="prefab" field={source} id="fileSource"/>
				<select([
					{value: EditMode.None, label: "None"},
					{value: EditMode.Edit, label: "Edit"},
					{value: EditMode.Override, label: "Override"}]) field={editMode} id="editModeSelect"/>
				<text("Warning : Edit mode enabled while there are override on this reference. Saving will cause the overrides to be applied to the original reference !") if(overrides != null && editMode == Edit)/>
			</category>
		);

		fileSource.onValueChange = (_) -> {
			ctx.rebuildPrefab(this);
		}

		editModeSelect.onValueChange = (_) -> {
			ctx.rebuildPrefab(this);
			ctx.rebuildTree(this);
			ctx.rebuildInspector();
		}

		super.edit2(ctx);

		var hasOverrides = computeDiffFromSource() != null;

		ctx.build(
			<category("Overrides")>
				<text(hasOverrides ? "This reference has overrides" : "No Overrides")/>
				<button("Clear Overrides") id="btnClearOverrides" disabled={!hasOverrides}/>
			</category>
		);

		btnClearOverrides.onClick = () -> {
			this.overrides = null;
			if (originalSource != null) {
				originalSource = null;
				refInstance = null;
				ctx.rebuildPrefab(this);
				ctx.rebuildInspector();
			}
		};

	}


	#if editor

	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor, scene: hide.comp.Scene) {
		super.setEditorChildren(sceneEditor, scene);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor, scene);
		}
	}

	override public function editorRemoveObjects() : Void {
		if (refInstance != null && wasMade) {
			for (child in refInstance.flatten()) {
				shared.editor.removeInteractive(child);
			}
			refInstance.editorRemoveObjects();
		}
		wasMade = false;
		super.editorRemoveObjects();
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
			pristineData = hrt.prefab.Diff.apply(pristineData, overrides);
		}

		originalSource = hrt.prefab.Diff.deepCopy(data);

		refInstance = Prefab.createFromDynamic(pristineData, new ContextShared(source, true));
		refInstance.shared.parentPrefab = this;
	}

	/**
		Returns true if this reference has a cycle,
		meaning that references depends on each other
	**/
	public function hasCycle() : Bool {

		function rec(prefab: Prefab, seenPaths: Map<String, Bool>) : Bool {
			if (prefab == null)
				return false;

			var ref = Std.downcast(prefab, Reference);
			if (ref != null && ref.source != null && ref.shouldBeInstanciated() && !ref.editorOnly) {
				if (seenPaths.get(ref.source) == true) {
					return true;
				}

				seenPaths.set(ref.source, true);
				if (rec(ref.resolve(), seenPaths.copy()))
					return true;
			}
			for (child in prefab.children) {
				if(rec(child, seenPaths.copy()))
					return true;
			}

			return false;
		}

		return rec(this, [this.shared.currentPath => true]);
	}

	override function makeInteractive() {
		if( editMode != None )
			return null;
		return super.makeInteractive();
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		var element = new hide.Element('
			<div class="group" name="Reference">
			<dl>
				<dt>Reference</dt><dd><input type="fileselect" extensions="prefab l3d fx" field="source"/></dd>
				<dt>Edit</dt><dd><select field="editMode" class="monSelector"></select></dd>
				<p class="warning">Warning : Edit mode enabled while there are override on this reference. Saving will cause the overrides to be applied to the original reference !</p>
			</dl>
			</div>');


		var warning = element.find(".warning");

		function updateProps() {
			var input = element.find("input");
			var found = resolve() != null;
			input.toggleClass("error", !found);
			warning.toggle(overrides != null && editMode == Edit);
		}
		updateProps();

		var props = ctx.properties.add(element, this, function(pname) {
			ctx.onChange(this, pname);
			if(pname == "source" || pname == "editMode") {

				var oldRefInst = refInstance;
				refInstance = null; // force resolve to return the new referenced prefab for hasCycle();
				var cycle = hasCycle();
				refInstance = oldRefInst;

				if (cycle) {
					hide.Ide.inst.quickError('Reference to $source would create a cycle. The reference change was aborted.');
					source = null;
					ctx.rebuildProperties();
					return;
				}
				updateProps();
				if(!ctx.properties.isTempChange) {
					if (pname == "source") {
						ctx.rebuildPrefab(this);
					}
					else {
						if (refInstance != null) {
							for (child in refInstance.flatten()) {
								shared.editor.removeInteractive(child);
							}
						}

						shared.editor.refreshInteractive(this);
						@:privateAccess shared.editor.refreshTree(All);
					}
				}
			}
		});

		super.edit(ctx);

		var over = new hide.Element('
			<div class="group" name="Overrides">
				<p class="override-infos"></p>
				<dl style="height: 100px;">
					<dt></dt><dd><fancy-button><span class="label">Clear Overrides</span></fancy-button></dd>
				</dl>
			</div>
		');

		var overInfos = over.find(".override-infos");
		function refreshOverrideInfos() {
			if (computeDiffFromSource() == null) {
				overInfos.text("No overrides");
			}
			else {
				overInfos.text("This reference has overrides");
			}
		}
		refreshOverrideInfos();

		over.find("fancy-button").click((_) -> {
			var old = overrides;
			this.overrides = null;
			var refresh = () -> {
				if (originalSource != null) {
					@:privateAccess shared.editor.removeInstance(refInstance, false);
					originalSource = null;
					refInstance = null;
					ctx.rebuildPrefab(this);
					refreshOverrideInfos();
				}
			};
			@:privateAccess ctx.properties.undo.change(Field(this, "overrides", old), refresh);
			refresh();
			ctx.rebuildPrefab(this);
		});
		ctx.properties.add(over);
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
						parents[i].children[childIndex] = clones[i];
						break;
					}
					editor.removeInstance(selectedRef, false);
					@:bypassAccessor clones[i].parent = parents[i];
					@:bypassAccessor selectedRef.parent = null;
					newSelection.push(clones[i]);
				}
				else {
					// find our clone in the parent children,
					// and swap it with the original prefab
					for (childIndex => prefab in parents[i].children) {
						if (prefab != clones[i]) continue;
						parents[i].children[childIndex] = selectedRef;
						break;
					}
					editor.removeInstance(clones[i], false);
					@:bypassAccessor clones[i].parent = null;
					@:bypassAccessor selectedRef.parent = parents[i];
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

	static function onContextMenu(selection: Array<hrt.prefab.Prefab>) : Array<hide.comp.ContextMenu.MenuItem> {
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