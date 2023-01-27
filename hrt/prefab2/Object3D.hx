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


	public static var modelCache : h3d.prim.ModelCache = new h3d.prim.ModelCache();

	public static function loadModel( path : String ) {
		return modelCache.loadModel(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	public static function loadAnimation( path : String ) {
		return @:privateAccess modelCache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
	}

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

    override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateParams) {
        local3d = new h3d.scene.Object(ctx.local3d);
		updateInstance();
    }

	override function updateInstance(?propName : String ) {
		applyTransform();
	}

    override function destroy() {
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

	override function makeInteractive() : hxd.SceneEvents.Interactive {
		var local3d = getLocal3d();
		if(local3d == null)
			return null;
		var meshes = [Std.downcast(local3d, h3d.scene.Mesh)];// ctx.shared.getObjects(this, h3d.scene.Mesh);
		var invRootMat = local3d.getAbsPos().clone();
		invRootMat.invert();
		var bounds = new h3d.col.Bounds();
		var localBounds = [];
		var totalSeparateBounds = 0.;
		var visibleMeshes = [];
		var hasSkin = false;

		inline function getVolume(b:h3d.col.Bounds) {
			var c = b.getSize();
			return c.x * c.y * c.z;
		}
		for(mesh in meshes) {
			if(mesh.ignoreCollide)
				continue;

			// invisible objects are ignored collision wise
			var p : h3d.scene.Object = mesh;
			while( p != local3d ) {
				if( !p.visible ) break;
				p = p.parent;
			}
			if( p != local3d ) continue;

			var localMat = mesh.getAbsPos().clone();
			localMat.multiply(localMat, invRootMat);

			if( mesh.primitive == null ) continue;
			visibleMeshes.push(mesh);

			if( Std.downcast(mesh, h3d.scene.Skin) != null ) {
				hasSkin = true;
				continue;
			}

			var lb = mesh.primitive.getBounds().clone();
			lb.transform(localMat);
			bounds.add(lb);

			totalSeparateBounds += getVolume(lb);
			for( b in localBounds ) {
				var tmp = new h3d.col.Bounds();
				tmp.intersection(lb, b);
				totalSeparateBounds -= getVolume(tmp);
			}
			localBounds.push(lb);
		}
		if( visibleMeshes.length == 0 )
			return null;
		var colliders = [for(m in visibleMeshes) {
			var c : h3d.col.Collider = try m.getGlobalCollider() catch(e: Dynamic) null;
			if(c != null) c;
		}];
		var meshCollider = colliders.length == 1 ? colliders[0] : new h3d.col.Collider.GroupCollider(colliders);
		var collider : h3d.col.Collider = new h3d.col.ObjectCollider(local3d, bounds);
		if( hasSkin ) {
			collider = meshCollider; // can't trust bounds
			meshCollider = null;
		} else if( totalSeparateBounds / getVolume(bounds) < 0.5 ) {
			collider = new h3d.col.Collider.OptimizedCollider(collider, meshCollider);
			meshCollider = null;
		}
		var int = new h3d.scene.Interactive(collider, local3d);
		int.ignoreParentTransform = true;
		int.preciseShape = meshCollider;
		int.propagateEvents = true;
		int.enableRightButton = true;
		return int;
	}

}