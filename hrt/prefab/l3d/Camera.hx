package hrt.prefab.l3d;
import hrt.prefab.Context;
import hrt.prefab.Library;

class Camera extends Object3D {

	var fovY : Float = 45;
	var zFar : Float = 200;
	var zNear : Float = 0.02;
	var showFrustum = true;

	public function new(?parent) {
		super(parent);
		type = "camera";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.fovY = fovY;
		obj.zFar = zFar;
		obj.zNear = zNear;
		obj.showFrustum = showFrustum;
		return obj;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		if(obj.fovY != null) this.fovY = obj.fovY;
		if(obj.zFar != null) this.zFar = obj.zFar;
		if(obj.zNear != null) this.zNear = obj.zNear;
		if(obj.showFrustum != null) this.showFrustum = obj.showFrustum;
	}

	var g : h3d.scene.Graphics;
	function drawFrustum( ctx : Context ) {

		if( !showFrustum ) {
			if( g != null ) {
				g.remove();
				g = null;
			}
			return;
		}

		if( g == null ) {
			g = new h3d.scene.Graphics(ctx.local3d);
			g.name = "frustumDebug";
			g.material.mainPass.setPassName("overlay");
		}

		var c = new h3d.Camera();
		c.pos.set(0,0,0);
		c.target.set(1,0,0);
		c.fovY = fovY;
		c.zFar = zFar;
		c.zNear = zNear;
		c.update();

		var nearPlaneCorner = [c.unproject(-1, 1, 0), c.unproject(1, 1, 0), c.unproject(1, -1, 0), c.unproject(-1, -1, 0)];
		var farPlaneCorner = [c.unproject(-1, 1, 1), c.unproject(1, 1, 1), c.unproject(1, -1, 1), c.unproject(-1, -1, 1)];

		g.clear();
		g.lineStyle(1, 0xffffff);

		// Near Plane
		var last = nearPlaneCorner[nearPlaneCorner.length - 1];
		g.moveTo(last.x,last.y,last.z);
		for( fc in nearPlaneCorner ) {
			g.lineTo(fc.x, fc.y, fc.z);
		}

		// Far Plane
		var last = farPlaneCorner[farPlaneCorner.length - 1];
		g.moveTo(last.x,last.y,last.z);
		for( fc in farPlaneCorner ) {
			g.lineTo(fc.x, fc.y, fc.z);
		}

		// Connections
		for( i in 0 ... 4 ) {
			var np = nearPlaneCorner[i];
			var fp = farPlaneCorner[i];
			g.moveTo(np.x, np.y, np.z);
			g.lineTo(fp.x, fp.y, fp.z);
		}

		// Connections to camera pos
		g.lineStyle(1, 0xff0000);
		for( i in 0 ... 4 ) {
			var np = nearPlaneCorner[i];
			g.moveTo(np.x, np.y, np.z);
			g.lineTo(0, 0, 0);
		}
	}

	override function updateInstance( ctx, ?p ) {
		super.updateInstance(ctx, p);
		drawFrustum(ctx);
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
		c.zNear = zNear;
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
					<dt>Z Far</dt><dd><input type="range" min="0" max="1000" field="zFar"/></dd>
					<dt>Z Near</dt><dd><input type="range" min="0" max="10" field="zNear"/></dd>
					<dt></dt><dd><input class="copy" type="button" value="Copy Current"/></dd>
					<dt></dt><dd><input class="preview" type="button" value="Preview" /></dd>
					<dt></dt><dd><input class="reset" type="button" value="Reset" /></dd>
				</dl>
			</div>
			<div class="group" name="Debug">
				<dl>
					<dt>Show Frustum</dt><dd><input type="checkbox" field="showFrustum"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
			if( pname != "showFrustum" ) {
				var c = ctx.scene.s3d.camera;
				if(c != null) {
					c.fovY = fovY;
					c.zFar = zFar;
					c.zNear = zNear;
					ctx.scene.editor.cameraController.lockZPlanes = true;
					ctx.scene.editor.cameraController.loadFromCamera();
				}
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
			this.zNear = cam.zNear;
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
