package hrt.prefab;

enum EditMode {
	/** The reference can't be edited in the editor **/
	None;

	/** The reference can be edited in the editor, and saving it will update the referenced prefab file on disk **/
	Edit;

	/** The reference can be edited, and saving it will save a diff between the original prefab and this in the `override` field **/
	Override;
}
class Reference extends Object3D {
	/**
		The referenced prefab loaded by this reference
	**/
	public var refInstance : Prefab;

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

	#if editor
	var wasMade : Bool = false;

	/**
		Copy of the original data to use as a reference on save for overrides
	**/
	public var originalSource : Dynamic;
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

		if (source != null && shouldBeInstanciated() && hxd.res.Loader.currentInstance.exists(source)) {
			#if editor
			if (hasCycle())
				return;
			#end
			initRefInstance();
		}
	}

	override function copy(obj: Prefab) {
		super.copy(obj);
		var otherRef : Reference = cast obj;

		#if editor
		originalSource = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab().loadData();
		#end

		// Clone the refInstance from the original prefab on copy
		if (source != null && shouldBeInstanciated()) {
			if (otherRef.refInstance != null) {
				refInstance = otherRef.refInstance.clone(new ContextShared(source, null, null, true));
			} else {
				initRefInstance();
			}
			refInstance?.shared.parentPrefab = this;
		}
	}

	#if editor
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
	#end

	function initRefInstance() {
		var refInstanceData = null;
		#if editor
		try {
		#end
		refInstanceData = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab().loadData();
		#if editor
		} catch (e) {

		}
		#end

		if (refInstanceData == null)
			return;

		#if editor
		originalSource = @:privateAccess hxd.res.Loader.currentInstance.load(source).toPrefab().loadData();
		#end

		if (overrides != null) {
			refInstanceData = hrt.prefab.Diff.apply(refInstanceData, overrides);
		}

		refInstance = hrt.prefab.Prefab.createFromDynamic(refInstanceData, null, new ContextShared(source, null, null, true));
		refInstance.shared.parentPrefab = this;
	}

	#if editor
	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor, scene: hide.comp.Scene) {
		super.setEditorChildren(sceneEditor, scene);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor, scene);
		}
	}
	#end

	#if editor
	function setRef(data: Dynamic) {
		if (data == null)
			throw "Null data";

		if (refInstance == null)
			return;

		var newSource = hrt.prefab.Diff.deepCopy(data);
		var currentSerialization = refInstance.serialize();

		var pristineData = hrt.prefab.Diff.deepCopy(newSource);

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

		originalSource = newSource;

		refInstance = Prefab.createFromDynamic(pristineData, new ContextShared(source, true));
		refInstance.shared.parentPrefab = this;
	}
	#end

	function resolveRef() : Prefab {
		var shouldLoad = refInstance == null && source != null && shouldBeInstanciated();

		#if editor
		if (hasCycle())
			shouldLoad = false;
		#end

		if (shouldLoad) {
			initRefInstance();
		}
		return refInstance;
	}

	override function makeInstance() {
		if( source == null )
			return;


		// in the case source has changed since the last load (can happen when creating references manually)
		if (refInstance?.shared.currentPath != source) {
			initRefInstance();
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

	override public function findRec<T:Prefab>(?cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false, includeDisabled: Bool = true) : Null<T> {
		if (!includeDisabled && !enabled)
			return null;
		var res = super.findRec(cl, filter, followRefs, includeDisabled);
		if (res == null && followRefs ) {
			var p = resolveRef();
			if( p != null )
				return p.findRec(cl, filter, followRefs, includeDisabled);
		}
		return res;
	}

	override public function getOpt<T:Prefab>( ?cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
		var res = super.getOpt(cl, name, followRefs);
		if (res == null && followRefs && resolveRef() != null) {
			return refInstance.getOpt(cl, name, followRefs);
		}
		return res;
	}

	override public function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T>) : Array<T> {
		arr = super.flatten(cl, arr);
		if (editMode != None && resolveRef() != null) {
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

	#if editor

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
		Returns true if this reference has a cycle,
		meaning that references depends on each other
	**/
	public function hasCycle() : Bool {

		var map : Map<String, Bool> = [];
		map.set(shared.currentPath, true);
		return hasCyclePath(source, map);
	}

	static function hasCyclePath(path: String, seenPaths: Map<String, Bool>) : Bool {
		if (seenPaths.get(path) == true)
			return true;
		if (!hxd.res.Loader.currentInstance.exists(path))
			return false;

		seenPaths.set(path, true);
		var data = @:privateAccess hxd.res.Loader.currentInstance.load(path).toPrefab().loadData();
		return hasCycleDynamic(data, seenPaths);
	}

	static function hasCycleDynamic(data: Dynamic, seenPaths: Map<String, Bool>) : Bool {
		if (data.source != null) {
			if (hasCyclePath(data.source, seenPaths.copy()))
				return true;
		}
		if (data.children) {
			for (child in (data.children:Array<Dynamic>)) {
				if (hasCycleDynamic(child, seenPaths)) {
					return true;
				}
			}
		}
		return false;
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
			var found = resolveRef() != null;
			input.toggleClass("error", !found);
			warning.toggle(overrides != null && editMode == Edit);
		}
		updateProps();

		var props = ctx.properties.add(element, this, function(pname) {
			ctx.onChange(this, pname);
			if(pname == "source" || pname == "editMode") {
				if (hasCycle()) {
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
						@:privateAccess shared.editor.refreshTree();
					}
				}
			}
		});

		super.edit(ctx);

		var over = new hide.Element('
			<div class="group">
				<dl>
					<dt>Overrides</dt><dd><p class="override-infos"></p><fancy-button><span class="label">Clear Overrides</span></fancy-button></dd>
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
			//ctx.rebuildPrefab(this);
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
			for (child in selectedRef.resolveRef().children) {
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
			editor.refreshTree();
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