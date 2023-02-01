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

    override private function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateContext) {
        super.makeInstance(ctx);

        if (path != null) {
            refInstance = Prefab.createFromPath(path).make(null, null, local3d);
        }
    }

    public static var _ = hrt.prefab2.Prefab.register("Reference", Reference);
}