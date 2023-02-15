package hrt.prefab2.l3d;
import hrt.prefab2.rfx.RendererFX;
import h3d.scene.Object;

// NOTE(ces) : Not Tested

class CameraSyncObject extends h3d.scene.Object {

	public var enable : Bool;
	public var fovY : Float;
	public var zFar : Float;
	public var zNear : Float;

	override function sync( ctx ) {
		if( enable ) {
			var c = getScene().camera;
			if( c != null ) {
				c.fovY = fovY;
				c.zFar = zFar;
				c.zNear = zNear;
			}
		}
	}
}

class Camera extends Object3D {

	@:s var fovY : Float = 45;
	@:s var zFar : Float = 200;
	@:s var zNear : Float = 0.02;
	@:s var showFrustum = false;
	var preview = false;
	var obj : h3d.scene.Object = null;
	#if editor
	var editContext : hide.prefab2.EditContext;
	#end

	public function new(?parent) {
		super(parent);
	}

	var g : h3d.scene.Graphics;
	function drawFrustum() {

		if( !showFrustum ) {
			if( g != null ) {
				g.remove();
				g = null;
			}
			return;
		}

		if( g == null ) {
			g = new h3d.scene.Graphics(local3d);
			g.name = "frustumDebug";
			g.material.mainPass.setPassName("overlay");
			g.ignoreBounds = true;
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

    override function makeObject3d(parent3d:Object):Object {
        var cam = new CameraSyncObject(parent3d);
        obj = cam;
        return obj;
    }

	override function updateInstance( ?p ) {
		applyRFX();
		super.updateInstance(p);
		#if editor
		drawFrustum();
		#end
		var cso = Std.downcast(local3d, CameraSyncObject);
		if( cso != null ) {
			cso.fovY = fovY;
			cso.zFar = zFar;
			cso.zNear = zNear;
			cso.enable = preview;
		}
		#if editor
		if ( preview ) {
			applyTo(editContext.scene.s3d.camera);
			editContext.scene.editor.cameraController.lockZPlanes = true;
			editContext.scene.editor.cameraController.loadFromCamera();
		}
		#end
	}

	public function applyTo(c: h3d.Camera) {
		var transform = null;
		if ( obj != null )
			transform = obj.getAbsPos();
		else
			transform = getAbsPos();
		c.setTransform(transform);
		var front = transform.front();
		var ray = h3d.col.Ray.fromValues(transform.getPosition().x, transform.getPosition().y, transform.getPosition().z, front.x, front.y, front.z);

		// this does not change camera rotation but allows for better navigation in editor
		var plane = h3d.col.Plane.Z();
		var pt = ray.intersect(plane);
		if( pt != null && pt.sub(c.pos.toPoint()).length() > 1 )
			c.target = pt.toVector();

		c.fovY = fovY;
		c.zFar = zFar;
		c.zNear = zNear;
	}

	function applyRFX() {
		if (local3d.getScene() == null) return;
		var renderer = local3d.getScene().renderer;
		if (renderer == null) return;
		if (preview) {

			for ( effect in getAll(hrt.prefab2.rfx.RendererFX) ) {
				var prevEffect = renderer.getEffect(hrt.prefab2.rfx.RendererFX);
				if ( prevEffect != null )
					renderer.effects.remove(prevEffect);
				renderer.effects.push( effect );
			}
		}
		else {
			for ( effect in getAll(hrt.prefab2.rfx.RendererFX) )
				renderer.effects.remove( effect );
		}
	}

	#if editor

	dynamic function setEditModeButton() {

	}

	function upgrade() {
		var parent = obj.parent;
		var transform = getTransform();
		if ( parent != null ) {
			var invPos = new h3d.Matrix();
			invPos._44 = 0;
			invPos.inverse3x4(parent.getAbsPos());
			transform.multiply(transform, invPos);
			setTransform(transform);
		}
	}

	override function setSelected(b : Bool ) {
		setEditModeButton();
		return false;
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);
		editContext = ctx;

		var props : hide.Element = ctx.properties.add(new hide.Element('
			<div class="group" name="Camera">
				<dl>
					<dt>Fov Y</dt><dd><input type="range" min="0" max="180" field="fovY"/></dd>
					<dt>Z Far</dt><dd><input type="range" min="0" max="1000" field="zFar"/></dd>
					<dt>Z Near</dt><dd><input type="range" min="0" max="10" field="zNear"/></dd>
					<dt></dt><dd><input class="copy" type="button" value="Copy Current"/></dd>
					<dt></dt><dd><input class="apply" type="button" value="Apply" /></dd>
					<dt></dt><dd><input class="reset" type="button" value="Reset" /></dd>
				</dl>
			</div>
			<div class="group" name="Debug">
				<dl>
					<dt>Show Frustum</dt><dd><input type="checkbox" field="showFrustum"/></dd>
					<div align="center">
						<input type="button" value="Preview Mode : Disabled" class="editModeButton" />
					</div>
				</dl>
			</div>
			<div class="group" name="Deprecation">
				<dl>
					<div align="center">
						<input type="button" value="Upgrade" class="upgrade" />
					</div>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});

		var editModeButton = props.find(".editModeButton");
		setEditModeButton = function () {
			editModeButton.val(preview ? "Preview Mode : Enabled" : "Preview Mode : Disabled");
			editModeButton.toggleClass("editModeEnabled", preview);
		};
		editModeButton.click(function(_) {
			preview = !preview;
			setEditModeButton();
			var cam = ctx.scene.s3d.camera;
			var renderer = @:privateAccess ctx.scene.s3d.renderer;
			if (preview) {
				updateInstance();
				applyTo(cam);
				for ( effect in getAll(hrt.prefab2.rfx.RendererFX) ) {
					var prevEffect = @:privateAccess renderer.getEffect(hrt.prefab2.rfx.RendererFX);
					if ( prevEffect != null )
						renderer.effects.remove(prevEffect);
					renderer.effects.push( effect );
				}
				ctx.scene.editor.cameraController.lockZPlanes = true;
				ctx.scene.editor.cameraController.loadFromCamera();
				renderer.effects.push(new hrt.prefab2.rfx.Border(0.02, 0x0000ff, 0.5));
			}
			else {
				for ( effect in getAll(hrt.prefab2.rfx.RendererFX) )
					renderer.effects.remove( effect );
				for ( effect in renderer.effects ) {
					if ( Std.isOfType(effect, hrt.prefab2.rfx.Border) ) {
						renderer.effects.remove(effect);
						break;
					}
				}
				ctx.makeChanges(this, function() {
					var transform = new h3d.Matrix();
					transform.identity();
					var q = new h3d.Quat();
					q.initDirection(cam.target.sub(cam.pos));
					var angles = q.toEuler();
					transform.rotate(angles.x, angles.y, angles.z);
					transform.translate(cam.pos.x, cam.pos.y, cam.pos.z);

					var parent = getParent(hrt.prefab2.Object3D);
					if ( parent != null ) {
						var invPos = new h3d.Matrix();
						invPos._44 = 0;
						invPos.inverse3x4(parent.getAbsPos());
						transform.multiply(transform, invPos);
					}
					setTransform(transform);
					this.zFar = cam.zFar;
					this.zNear = cam.zNear;
					this.fovY = cam.fovY;
				});
			}
		});

		var deprecationButton = props.find(".upgrade");
		deprecationButton.click(function(_) {
			ctx.makeChanges(this, function() {
				upgrade();
			});
		});

		props.find(".copy").click(function(e) {
			var cam = ctx.scene.s3d.camera;
			ctx.makeChanges(this, function() {
				var transform = new h3d.Matrix();
				transform.identity();
				var q = new h3d.Quat();
				q.initDirection(cam.target.sub(cam.pos));
				var angles = q.toEuler();
				transform.rotate(angles.x, angles.y, angles.z);
				transform.translate(cam.pos.x, cam.pos.y, cam.pos.z);

				var parent = getParent(hrt.prefab2.Object3D);
				if ( parent != null ) {
					var invPos = new h3d.Matrix();
					invPos._44 = 0;
					invPos.inverse3x4(parent.getAbsPos());
					transform.multiply(transform, invPos);
				}
				setTransform(transform);
				this.zFar = cam.zFar;
				this.zNear = cam.zNear;
				this.fovY = cam.fovY;
			});
		});


		props.find(".apply").click(function(e) {
			applyTo(ctx.scene.s3d.camera);
			ctx.scene.editor.cameraController.lockZPlanes = true;
			ctx.scene.editor.cameraController.loadFOVFromCamera();
			ctx.scene.editor.cameraController.loadFromCamera(true);
		});

		props.find(".reset").click(function(e) {
			ctx.scene.editor.resetCamera();
		});
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "video-camera", name : "Camera" };
	}
	#end

	static var _ = Prefab.register("camera", Camera);

}
