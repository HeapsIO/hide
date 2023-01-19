package hrt.prefab2;
import hxd.Math;

class Object3D extends Prefab {
    @:s @:range(0,400) public var x(default, set) : Float = 0.0;
    @:s @:range(0,400) public var y(default, set) : Float = 0.0;
    @:s @:range(0,400) public var z(default, set) : Float = 0.0;

    @:s public var rotationX : Float = 0.0;
    @:s public var rotationY : Float = 0.0;
    @:s public var rotationZ : Float = 0.0;

    @:s public var scaleX : Float = 1.0;
    @:s public var scaleY : Float = 1.0;
    @:s public var scaleZ : Float = 1.0;

    @:s public var visible : Bool = true;


	static var cache : h3d.prim.ModelCache = new h3d.prim.ModelCache();


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

    override function onMakeInstance() {
        local3d = new h3d.scene.Object(parent.getFirstLocal3d());
		applyTransform();
    }

    override function onDestroy() {
        if (local3d != null) local3d.remove();
    }

    public function setTransform(mat : h3d.Matrix) {
		var rot = mat.getEulerAngles();
		x = mat.tx;
		y = mat.ty;
		z = mat.tz;
		var s = mat.getScale();
		scaleX = s.x;
		scaleY = s.y;
		scaleZ = s.z;
		rotationX = Math.radToDeg(rot.x);
		rotationY = Math.radToDeg(rot.y);
		rotationZ = Math.radToDeg(rot.z);
	}

    public static var _ = Prefab.register("object3D", Object3D);

	public function saveTransform() {
		return { x : x, y : y, z : z, scaleX : scaleX, scaleY : scaleY, scaleZ : scaleZ, rotationX : rotationX, rotationY : rotationY, rotationZ : rotationZ };
	}

    public function applyTransform() {
		var o = getLocal3d();
		if (o == null) return;
		o.x = x;
		o.y = y;
		o.z = z;
		o.scaleX = scaleX;
		o.scaleY = scaleY;
		o.scaleZ = scaleZ;
		o.setRotation(Math.degToRad(rotationX), Math.degToRad(rotationY), Math.degToRad(rotationZ));
	}

    public function getTransform( ?m: h3d.Matrix ) {
		if( m == null ) m = new h3d.Matrix();
		m.initScale(scaleX, scaleY, scaleZ);
		m.rotate(Math.degToRad(rotationX), Math.degToRad(rotationY), Math.degToRad(rotationZ));
		m.translate(x, y, z);
		return m;
	}

    public function localRayIntersection(ray : h3d.col.Ray ) : Float {
		return -1;
	}

    public function loadTransform(t) {
		x = t.x;
		y = t.y;
		z = t.z;
		scaleX = t.scaleX;
		scaleY = t.scaleY;
		scaleZ = t.scaleZ;
		rotationX = t.rotationX;
		rotationY = t.rotationY;
		rotationZ = t.rotationZ;
	}

	public function getDisplayFilters() : Array<String> {
		return [];
	}

}