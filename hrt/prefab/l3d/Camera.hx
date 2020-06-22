package hrt.prefab.l3d;
import hrt.prefab.Context;
import hrt.prefab.Library;

class Camera extends Object3D {

	var fovY : Float = 45;
	var zFar : Float = 150;

	public function new(?parent) {
		super(parent);
		type = "camera";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.fovY = fovY;
		obj.zFar = zFar;
		return obj;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		if(obj.fovY != null) this.fovY = obj.fovY;
		if(obj.zFar != null) this.zFar = obj.zFar;
	}

	public function applyTo(c: h3d.Camera) {
		var front = getTransform().front();
		var ray = h3d.col.Ray.fromValues(x, y, z, front.x, front.y, front.z);
		c.pos.set(x, y, z);
		c.target = c.pos.add(front);

		// this does not change camera rotation but allows for better navigation in editor
		var plane = h3d.col.Plane.Z();
		var pt = ray.intersect(plane);
		if( pt != null && pt.sub(c.pos.toPoint()).length() > 1 )
			c.target = pt.toVector();

		c.fovY = fovY;
		c.zFar = zFar;
	}

	#if editor

	override function setSelected( ctx : Context, b : Bool ) {
		return false;
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props : hide.Element = ctx.properties.add(new hide.Element('
			<div class="group" name="Camera">
				<dl>
					<dt>Fov Y</dt><dd><input type="range" min="0" max="180" field="fovY"/></dd>
					<dt>Z Far</dt><dd><input type="range" min="0" max="180" field="zFar"/></dd>
					<dt></dt><dd><input class="copy" type="button" value="Copy Current"/></dd>
					<dt></dt><dd><input class="preview" type="button" value="Preview" /></dd>
					<dt></dt><dd><input class="reset" type="button" value="Reset" /></dd>
				</dl>
			</div>
		'),this, function(pname) {
			var c = ctx.scene.s3d.camera;
			if(c != null) {
				c.fovY = fovY;
				c.zFar = zFar;
				ctx.scene.editor.cameraController.lockZPlanes = true;
				ctx.scene.editor.cameraController.loadFromCamera();
			}
		});

		props.find(".copy").click(function(e) {
			var cam = ctx.scene.s3d.camera;
			var q = new h3d.Quat();
			q.initDirection(cam.target.sub(cam.pos));
			var angles = q.toEuler();
			this.rotationX = hxd.Math.fmt(angles.x * 180 / Math.PI);
			this.rotationY = hxd.Math.fmt(angles.y * 180 / Math.PI);
			this.rotationZ = hxd.Math.fmt(angles.z * 180 / Math.PI);
			this.scaleX = this.scaleY = this.scaleZ = 1;
			this.x = hxd.Math.fmt(cam.pos.x);
			this.y = hxd.Math.fmt(cam.pos.y);
			this.z = hxd.Math.fmt(cam.pos.z);
			this.zFar = cam.zFar;
			this.fovY = cam.fovY;
			applyTo(cam);
			ctx.scene.editor.cameraController.lockZPlanes = true;
			ctx.scene.editor.cameraController.loadFromCamera();
			ctx.rebuildProperties();
		});


		props.find(".preview").click(function(e) {
			applyTo(ctx.scene.s3d.camera);
			ctx.scene.editor.cameraController.lockZPlanes = true;
			ctx.scene.editor.cameraController.loadFromCamera();
		});

		props.find(".reset").click(function(e) {
			ctx.scene.editor.resetCamera();
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "cogs", name : "Camera" };
	}
	#end

	static var _ = Library.register("camera", Camera);

}
