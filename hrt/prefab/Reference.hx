package hrt.prefab;

class Reference extends Object3D {
	@:s public var editMode : Bool = false;

	public var refInstance : Prefab;



	//@:s @:copy(copy_overrides)
	//public var overrides : haxe.ds.StringMap<Dynamic> = new haxe.ds.StringMap<Dynamic>();

	/*override public function getLocal2d() : h2d.Object {
		return refInstance != null ? refInstance.getLocal2d() : null;
	}

	override public function getLocal3d() : h3d.scene.Object {
		return refInstance != null ? refInstance.getLocal3d() : null;
	}*/

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

	override public function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		arr = super.flatten(cl, arr);
		if (refInstance != null) {
			arr = refInstance.flatten(cl, arr);
		}
		return arr;
	}

	function resolveRef() : Prefab {
		if(source == null)
			return null;
		if (refInstance != null)
			return refInstance;
		var p = Prefab.loadPath(source);
		return p;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		if (source != null) {
			var p = resolveRef();
			var sh = Prefab.createContextShared();
			sh.currentPath = source;
			sh.parent = this;
			sh.customMake = this.shared.customMake;
			#if editor
			p.setEditor((cast shared:hide.prefab.ContextShared).editor);
			#end
			if (p.to(Object3D) != null) {
			refInstance = p.make(null, findFirstLocal2d(), parent3d, sh);
		return Object3D.getLocal3d(refInstance);
			} else {
				var local3d = new h3d.scene.Object(parent3d);
				refInstance = p.make(null, findFirstLocal2d(), local3d, sh);
				return local3d;
			}
		}
		return null;
	}

	override public function findAll<T>( f : Prefab -> Null<T>, followRefs : Bool = false, ?arr : Array<T> ) : Array<T> {
		arr = super.findAll(f, followRefs, arr);

		if (followRefs && refInstance != null) {
			return refInstance.findAll(f, followRefs, arr);
		}

		return arr;
	}

	override public function find<T>( f : Prefab -> Null<T>, followRefs : Bool = false ) : Null<T> {
		var res = super.find(f, followRefs);
		if (res == null && followRefs && refInstance != null) {
			return refInstance.find(f, followRefs);
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

	#if editor
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
	#end


	public static var _ = hrt.prefab.Prefab.register("reference", Reference);
}