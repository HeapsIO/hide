package hrt.prefab;

class Reference extends Object3D {
	@:s public var editMode : Bool = false;

	public var refInstance : Prefab;

	public static function copy_overrides(from:Dynamic) : haxe.ds.StringMap<Dynamic> {
		if (Std.isOfType(from, haxe.ds.StringMap)) {
			return from != null ? cast(from, haxe.ds.StringMap<Dynamic>).copy() : new haxe.ds.StringMap<Dynamic>();
		}
		else {
			var m = new haxe.ds.StringMap<Dynamic>();
			for (f in Reflect.fields(from)) {
				m.set(f, Reflect.getProperty(from ,f));
			}
			return m;
		}
	}

	override function save() {
		var obj : Dynamic = super.save();
		#if editor
		if( editMode && refInstance != null ) {
			var sheditor = Std.downcast(shared, hide.prefab.ContextShared);
			if( sheditor.editor != null ) sheditor.editor.watchIgnoreChanges(source);

			var s = refInstance.serialize();
			sys.io.File.saveContent(hide.Ide.inst.getPath(source), hide.Ide.inst.toJSON(s));
		}
		#end
		return obj;
	}

	#if editor
	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor, scene: hide.comp.Scene) {
		super.setEditorChildren(sceneEditor, scene);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor, scene);
		}
	}
	#end

	function resolveRef() : Prefab {
		if(source == null)
			return null;
		if (refInstance != null)
			return refInstance;
		#if editor
		try {
		#end
			var refInstance = hxd.res.Loader.currentInstance.load(source).to(hrt.prefab.Resource).load().clone();
			refInstance.shared.parentPrefab = this;
			return refInstance;
		#if editor
		} catch (_) {
			return null;
		}
		#end
	}

	override function makeInstance() {
		if( source == null )
			return;
		#if editor
		if (hasCycle()) {
			hide.Ide.inst.quickError('Reference ${getAbsPath()} to $source is creating a cycle. Please fix the reference.');
			refInstance = null;
			return;
		}
		#end

		var p = resolveRef();
		var refLocal3d : h3d.scene.Object = null;

		if (Std.downcast(p, Object3D) != null) {
			refLocal3d = shared.current3d;
		} else {
			super.makeInstance();
			refLocal3d = local3d;
		}

		if (p == null) {
			refInstance = null;
			return;
		}

		var sh = p.shared;
		@:privateAccess sh.root3d = sh.current3d = refLocal3d;
		@:privateAccess sh.root2d = sh.current2d = findFirstLocal2d();

		#if editor
		sh.editor = this.shared.editor;
		sh.scene = this.shared.scene;
		#end
		sh.parentPrefab = this;
		sh.customMake = this.shared.customMake;
		refInstance = p;

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
	}


	override public function find<T:Prefab>(?cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false ) : Null<T> {
		var res = super.find(cl, filter, followRefs);
		if (res == null && followRefs ) {
			var p = resolveRef();
			if( p != null )
				return p.find(cl, filter, followRefs);
		}
		return res;
	}

	override public function getOpt<T:Prefab>( ?cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
		var res = super.getOpt(cl, name, followRefs);
		if (res == null && followRefs && refInstance != null) {
			return refInstance.getOpt(cl, name, followRefs);
		}
		return res;
	}

	override public function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		arr = super.flatten(cl, arr);
		if (editMode && refInstance != null) {
			arr = refInstance.flatten(cl, arr);
		}
		return arr;
	}

	override function dispose() {
		super.dispose();
		if( refInstance != null )
			refInstance.dispose();
	}

	#if editor

	override public function editorRemoveObjects() : Void {
		if (refInstance != null) {
			refInstance.editorRemoveObjects();
		}
		super.editorRemoveObjects();
	}

	public function hasCycle(?seenPaths: Map<String, Bool>) : Bool {
		if (editorOnly)
			return false;
		var oldEditMode = editMode;
		editMode = false;
		seenPaths = seenPaths?.copy() ?? [];
		var curPath = this.shared.currentPath;
		if (seenPaths.get(curPath) != null) {
			editMode = oldEditMode;
			return true;
		}
		seenPaths.set(curPath, true);

		if (source != null) {
			var ref = resolveRef();
			if (ref != null) {
				var root = ref;
				if (Std.isOfType(root, hrt.prefab.fx.BaseFX)) {
					root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(root) ?? root;
				}

				var allRefs = root.flatten(Reference);
				for (r in allRefs) {
					if (r.hasCycle(seenPaths)){
						editMode = oldEditMode;
						return true;
					}
				}
			}
		}
		editMode = oldEditMode;
		return false;
	}

	override function makeInteractive() {
		if( editMode )
			return null;
		return super.makeInteractive();
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		var element = new hide.Element('
			<div class="group" name="Reference">
			<dl>
				<dt>Reference</dt><dd><input type="fileselect" extensions="prefab l3d fx" field="source"/></dd>
				<dt>Edit</dt><dd><input type="checkbox" field="editMode"/></dd>
			</dl>
			</div>');

		function updateProps() {
			var input = element.find("input");
			var found = resolveRef() != null;
			input.toggleClass("error", !found);
		}
		updateProps();

		var props = ctx.properties.add(element, this, function(pname) {
			ctx.onChange(this, pname);
			if(pname == "source" || pname == "editMode") {
				if (pname == "source") {
					editorRemoveObjects();
					refInstance = null;
				}
				if (hasCycle()) {
					hide.Ide.inst.quickError('Reference to $source would create a cycle. The reference change was aborted.');
					ctx.properties.undo.undo();
					@:privateAccess ctx.properties.undo.redoElts.pop();
					return;
				}
				updateProps();
				if(!ctx.properties.isTempChange) {
					if (pname == "source") {
						ctx.rebuildPrefab(this);
					}
					else {
						@:privateAccess shared.editor.refreshTree();
					}
				}
			}
		});

		super.edit(ctx);
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "share", name : "Reference" };
	}
	#end


	public static var _ = hrt.prefab.Prefab.register("reference", Reference);
}