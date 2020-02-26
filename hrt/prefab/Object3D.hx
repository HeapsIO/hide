package hrt.prefab;
import hxd.Math;
using Lambda;

class Object3D extends Prefab {

	public var x : Float = 0.;
	public var y : Float = 0.;
	public var z : Float = 0.;
	public var scaleX : Float = 1.;
	public var scaleY : Float = 1.;
	public var scaleZ : Float = 1.;
	public var rotationX : Float = 0.;
	public var rotationY : Float = 0.;
	public var rotationZ : Float = 0.;
	public var visible : Bool = true;

	public function new(?parent) {
		super(parent);
		type = "object";
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

	public function saveTransform() {
		return { x : x, y : y, z : z, scaleX : scaleX, scaleY : scaleY, scaleZ : scaleZ, rotationX : rotationX, rotationY : rotationY, rotationZ : rotationZ };
	}

	override function load( obj : Dynamic ) {
		x = obj.x == null ? 0. : obj.x;
		y = obj.y == null ? 0. : obj.y;
		z = obj.z == null ? 0. : obj.z;

		scaleX = obj.scaleX == null ? 1. : obj.scaleX;
		scaleY = obj.scaleY == null ? 1. : obj.scaleY;
		scaleZ = obj.scaleZ == null ? 1. : obj.scaleZ;

		rotationX = obj.rotationX == null ? 0. : obj.rotationX;
		rotationY = obj.rotationY == null ? 0. : obj.rotationY;
		rotationZ = obj.rotationZ == null ? 0. : obj.rotationZ;

		visible = obj.visible == null ? true : obj.visible;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function save() {
		var o : Dynamic = {};
		if( x != 0 ) o.x = x;
		if( y != 0 ) o.y = y;
		if( z != 0 ) o.z = z;
		if( scaleX != 1 ) o.scaleX = scaleX;
		if( scaleY != 1 ) o.scaleY = scaleY;
		if( scaleZ != 1 ) o.scaleZ = scaleZ;
		if( rotationX != 0 ) o.rotationX = rotationX;
		if( rotationY != 0 ) o.rotationY = rotationY;
		if( rotationZ != 0 ) o.rotationZ = rotationZ;
		if( !visible ) o.visible = visible;
		return o;
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


	public function getTransform( ?m: h3d.Matrix ) {
		if( m == null ) m = new h3d.Matrix();
		m.initScale(scaleX, scaleY, scaleZ);
		m.rotate(Math.degToRad(rotationX), Math.degToRad(rotationY), Math.degToRad(rotationZ));
		m.translate(x, y, z);
		return m;
	}

	public function applyPos( o : h3d.scene.Object ) {
		o.x = x;
		o.y = y;
		o.z = z;
		o.scaleX = scaleX;
		o.scaleY = scaleY;
		o.scaleZ = scaleZ;
		o.setRotation(Math.degToRad(rotationX), Math.degToRad(rotationY), Math.degToRad(rotationZ));
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		var o = ctx.local3d;
		applyPos(o);
		o.visible = visible;
	}

	override function removeInstance(ctx: Context):Bool {
		if(ctx.local3d != null)
			ctx.local3d.remove();
		return true;
	}

	#if editor
	public function makeInteractive( ctx : Context ) : h3d.scene.Interactive {
		var local3d = ctx.local3d;
		if(local3d == null)
			return null;
		var meshes = ctx.shared.getObjects(this, h3d.scene.Mesh);
		var invRootMat = local3d.getAbsPos().clone();
		invRootMat.invert();
		var bounds = new h3d.col.Bounds();
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
			var lb = mesh.primitive.getBounds().clone();
			lb.transform(localMat);
			bounds.add(lb);
		}
		var meshCollider = new h3d.col.Collider.GroupCollider([for(m in meshes) {
			var c : h3d.col.Collider = try m.getGlobalCollider() catch(e: Dynamic) null;
			if(c != null) c;
		}]);
		var boundsCollider = new h3d.col.ObjectCollider(local3d, bounds);
		var int = new h3d.scene.Interactive(boundsCollider, local3d);
		int.ignoreParentTransform = true;
		int.preciseShape = meshCollider;
		int.propagateEvents = true;
		int.enableRightButton = true;
		return int;
	}

	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="Position">
				<dl>
					<dt>X</dt><dd><input type="range" min="-10" max="10" value="0" field="x"/></dd>
					<dt>Y</dt><dd><input type="range" min="-10" max="10" value="0" field="y"/></dd>
					<dt>Z</dt><dd><input type="range" min="-10" max="10" value="0" field="z"/></dd>
					<dt>Scale X</dt><dd><input type="range" min="0" max="5" value="1" field="scaleX"/></dd>
					<dt>Scale Y</dt><dd><input type="range" min="0" max="5" value="1" field="scaleY"/></dd>
					<dt>Scale Z</dt><dd><input type="range" min="0" max="5" value="1" field="scaleZ"/></dd>
					<dt>Rotation X</dt><dd><input type="range" min="-180" max="180" value="0" field="rotationX" /></dd>
					<dt>Rotation Y</dt><dd><input type="range" min="-180" max="180" value="0" field="rotationY" /></dd>
					<dt>Rotation Z</dt><dd><input type="range" min="-180" max="180" value="0" field="rotationZ" /></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		// Check children
		return {
			icon : children == null || children.length > 0 ? "folder-open" : "genderless",
			name : "Group"
		};
	}
	#end

	override function getDefaultName() {
		return type == "object" ? "group" : super.getDefaultName();
	}

	static var _ = Library.register("object", Object3D);

}