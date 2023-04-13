package hrt.prefab2;

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

	#if editor
	override function setEditorChildren(sceneEditor:hide.comp2.SceneEditor) {
		super.setEditorChildren(sceneEditor);

		if (refInstance != null) {
			refInstance.setEditor(sceneEditor);
		}
	}
	#end

	function resolveRef() : Prefab {
		if(source == null)
			return null;
		var p = Prefab.createFromPath(source);
		return p;
	}

	override function makeObject3d(parent3d: h3d.scene.Object) : h3d.scene.Object {
		if (source != null) {
			var p = resolveRef();
			var sh = Prefab.createContextShared();
			sh.parent = this;
			#if editor
			p.setEditor((cast shared:hide.prefab2.ContextShared).editor);
			#end
			refInstance = p.make(null, findFirstLocal2d(), parent3d, shared);
		}
		return Object3D.getLocal3d(refInstance);
	}

	override public function findAll<T>( f : Prefab -> Null<T>, ?followRefs : Bool, ?arr : Array<T> ) : Array<T> {
		arr = super.findAll(f, followRefs, arr);

		if (followRefs && refInstance != null) {
			return refInstance.findAll(f, followRefs, arr);
		}

		return arr;
	}

	override public function find<T>( f : Prefab -> Null<T>, ?followRefs : Bool ) : Null<T> {
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
	override function edit( ctx : hide.prefab2.EditContext ) {
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


	public static var _ = hrt.prefab2.Prefab.register("reference", Reference);
}