package hrt.prefab2;

class Reference extends Prefab {
    @:s public var path : String = null;

    //@:s @:copy(copy_overrides)
    //public var overrides : haxe.ds.StringMap<Dynamic> = new haxe.ds.StringMap<Dynamic>();

    override public function getLocal2d() : h2d.Object {
        return pref != null ? pref.getLocal2d() : null;
    }

    @:s
    public var test : Array<Int> = [];

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

    public var pref : Prefab = null;

    override private function onMake() {
        if (path != null) {
            pref = Prefab.loadFromPath(path).make(this);
        }
    }

    public static var _ = prefab2.Prefab.register("Reference", Reference);
}