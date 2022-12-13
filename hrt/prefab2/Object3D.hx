package hrt.prefab2;

class Object3D extends Prefab {
    @:s @:range(0,400)
    public var x(default, set) : Float = 0.0;

    @:s @:range(0,400)
    public var y(default, set) : Float = 0.0;

    @:s @:range(0,400)
    public var z(default, set) : Float = 0.0;

    /**Control the scale**/
    @:s @:range(0.5,4.0)
    public var scale(default, set) : Float = 1.0;

    public var local3d : h3d.scene.Object;

    override public function getLocal3d() : h3d.scene.Object {
        return local3d;
    }

    function set_x(v : Float) {
        x = v;
        local3d.x = x;
        return x;
    }

    function set_y(v : Float) {
        y = v;
        local3d.y = y;
        return y;
    }

    function set_z(v : Float) {
        z = v;
        local3d.z = z;
        return z;
    }

    function set_scale(v : Float) {
        scale = v;
        local3d.scaleX = local3d.scaleY = local3d.scaleZ = scale;
        return scale;
    }

    override function onMake() {
        local3d = new h3d.scene.Object(parent.getFirstLocal3d());
    }

    override function onDestroy() {
        if (local3d != null) local3d.remove();
    }

    public static var _ = Prefab.register("object3D", Object3D);

}