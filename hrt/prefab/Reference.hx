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

	override function save(obj : Dynamic) {
		var obj : Dynamic = super.save(obj);
		#if editor
		if( editMode && refInstance != null ) {
			var sheditor = Std.downcast(shared, hide.prefab.ContextShared);
			if( sheditor.editor != null ) sheditor.editor.watchIgnoreChanges(source);

			var s = refInstance.serializeToDynamic();
			sys.io.File.saveContent(hide.Ide.inst.getPath(source), hide.Ide.inst.toJSON(s));
		}
		#end
		return obj;
	}

	#if editor
	override function setEditorChildren(sceneEditor:hide.comp.SceneEditor) {
		super.setEditorChildren(sceneEditor);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor);
		}
	}
	#end

	function resolveRef() : Prefab {
		if(source == null)
			return null;
		if (refInstance != null)
			return refInstance;
		return hxd.res.Loader.currentInstance.load(source).to(hrt.prefab.Resource).load();
	}

	override function makeInstance() {
		if( source == null )
			return;
		var p = resolveRef();
		var refLocal3d : h3d.scene.Object = null;

		if (p.to(Object3D) != null) {
			refLocal3d = shared.current3d;
		} else {
			super.makeInstance();
			refLocal3d = local3d;
		}

		#if editor
		p.setEditor(this.shared.editor);
		#end
		var sh = new ContextShared(findFirstLocal2d(), refLocal3d);
		sh.currentPath = source;
		sh.parent = this;
		sh.customMake = this.shared.customMake;
		refInstance = p.clone(null, sh);

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

	override public function find<T:Prefab>(cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false ) : Null<T> {
		var res = super.find(cl, filter, followRefs);
		if (res == null && followRefs ) {
			var p = resolveRef();
			if( p != null )
				return p.find(cl, filter, followRefs);
		}
		return res;
	}

	override public function getOpt<T:Prefab>( cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
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
				refInstance = null;
				updateProps();
				if(!ctx.properties.isTempChange)
					ctx.rebuildPrefab(this);
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