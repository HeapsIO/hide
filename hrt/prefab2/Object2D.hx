package hrt.prefab2;
import hxd.Math;

class Object2D extends Prefab {
	@:s @:range(0,400) public var x(default, set) : Float = 0.;
	@:s @:range(0,400) public var y(default, set) : Float = 0.;
	@:s public var scaleX : Float = 1.;
	@:s public var scaleY : Float = 1.;
	@:s public var rotation : Float = 0.;

    @:s public var visible : Bool = true;

    public var local2d : h2d.Object;

    public static function getLocal2d(prefab: Prefab) : h2d.Object {
		var obj2d = Std.downcast(prefab, Object2D);
		if (obj2d != null)
			return obj2d.local2d;
		return null;
	}

    function set_x(v : Float) {
        x = v;
        local2d.x = x;
        return x;
    }

    function set_y(v : Float) {
        y = v;
        local2d.y = y;
        return y;
    }

    override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateParams) {
        local2d = new h2d.Object(ctx.local2d);
    }

    override function destroy() {
        if (local2d != null) local2d.remove();
    }

    public static var _ = Prefab.register("object2D", Object2D);

    public function loadTransform(t) {
		x = t.x;
		y = t.y;
		scaleX = t.scaleX;
		scaleY = t.scaleY;
		rotation = t.rotation;
	}

	public function saveTransform() {
		return { x : x, y : y, scaleX : scaleX, scaleY : scaleY, rotation : rotation };
	}

	public function setTransform(t) {
		x = t.x;
		y = t.y;
		scaleX = t.scaleX;
		scaleY = t.scaleY;
		rotation = t.rotation;
	}

    public function applyTransform( o : h2d.Object ) {
		o.x = x;
		o.y = y;
		o.scaleX = scaleX;
		o.scaleY = scaleY;
		o.rotation = Math.degToRad(rotation);
	}

}