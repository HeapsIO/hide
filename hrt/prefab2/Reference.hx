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

	function resolveRef() : Prefab {
		if(refInstance == null && source != null) {
			refInstance = Prefab.createFromPath(source);
			refInstance.shared = shared;
		}
		return refInstance;
	}

	override function makeObject3d(parent3d: h3d.scene.Object) : h3d.scene.Object {
		if (source != null) {
			resolveRef();
			refInstance.make(null, null, parent3d);
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


	public static var _ = hrt.prefab2.Prefab.register("reference", Reference);
}