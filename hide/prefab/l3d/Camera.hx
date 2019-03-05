package hide.prefab.l3d;
import hxd.prefab.Context;
import hxd.prefab.Library;


class Camera extends hide.prefab.Object3D {

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
		var plane = h3d.col.Plane.Z();
		var pt = ray.intersect(plane);
		c.pos.set(x, y, z);
		if(pt != null)
			c.target = pt.toVector();
		else
			c.target = c.pos.add(front);
		c.fovY = fovY;
		c.zFar = zFar;
	}


	#if editor

	override function setSelected( ctx : hide.prefab.Context, b : Bool ) {

	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props : hide.Element = ctx.properties.add(new hide.Element('
			<div class="group" name="Camera">
				<dl>
					<dt>Fov Y</dt><dd><input type="range" min="0" max="180" field="fovY"/></dd>
					<dt>Z Far</dt><dd><input type="range" min="0" max="180" field="zFar"/></dd>
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

		props.find(".preview").click(function(e) {
			applyTo(ctx.scene.s3d.camera);
			ctx.scene.editor.cameraController.lockZPlanes = true;
			ctx.scene.editor.cameraController.loadFromCamera();
		});

		props.find(".reset").click(function(e) {
			ctx.scene.s3d.camera.zFar = 150;
			ctx.scene.editor.cameraController.lockZPlanes = false;
			ctx.scene.editor.cameraController.loadFromCamera();
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "cogs", name : "Camera" };
	}
	#end

	static var _ = Library.register("camera", Camera);

}
