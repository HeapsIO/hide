package hrt.prefab2;

class Reference extends Object3D {
    @:s public var path : String = null;
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
        if(refInstance == null && path != null) {
            refInstance = Prefab.createFromPath(path);
        }
        return refInstance;
    }

    override function makeObject3d(parent3d: h3d.scene.Object) : h3d.scene.Object {
        if (path != null) {
            resolveRef();
            refInstance.make(null, null, parent3d);
        }
        return Object3D.getLocal3d(refInstance);
    }



    public static var _ = hrt.prefab2.Prefab.register("Reference", Reference);
}