package hrt.tools;
import hxd.Math;
import hxd.Key as K;

enum EditMode {
	Full;
	Translation;
	Rotation;
	Scale;
}

enum Handle {
	XArrow;
	YArrow;
	ZArrow;
	XRing;
	YRing;
	ZRing;
	XYPlane;
	XZPlane;
	YZPlane;
	Center;
}

class RotateAxisShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			@var var dir : Vec3;
		};
		@global var global : {
			@perObject var modelView : Mat4;
		};

		var transformedPosition : Vec3;
		var modelView : Mat4;
		var pixelColor : Vec4;

		function fragment() {
			var center = vec3(global.modelView[0].w, global.modelView[1].w, global.modelView[2].w);
			var camDir = camera.dir * -1;
			var dot = dot(camDir, (center - transformedPosition).normalize());
			pixelColor.a = ceil(clamp(dot, -0.15, 1) + 0.15);
		}
	}
}

class RotateSphereShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			@var var dir : Vec3;
		};
		@global var global : {
			@perObject var modelView : Mat4;
		};

		var transformedPosition : Vec3;
		var modelView : Mat4;
		var pixelColor : Vec4;

		function fragment() {
			var center = vec3(global.modelView[0].w, global.modelView[1].w, global.modelView[2].w);
			var camDir = camera.dir * -1;
			var dot = dot(camDir, (center - transformedPosition).normalize());
			pixelColor.a = dot < 0.2 && dot > -0.2 ? 1 : 0;
		}
	}
}

class Gizmo extends h3d.scene.Object {
	public static final X_COLOR = 0xfff44336;
	public static final Y_COLOR = 0xff4dae51;
	public static final Z_COLOR = 0xff2196f3;
	public static final DEFAULT_COLOR = 0xFFAAAAAA;

	public var mode : EditMode = Translation;
	public var isLocalTransform : Bool = false;

	public var onStartMove : Handle -> Void;
	public var onMove : (offsetPosition: h3d.Vector, offsetRotation: h3d.Quat, offsetScale: h3d.Vector) -> Void;
	public var onFinishMove : Void -> Void;

	var window(get, never) : hxd.Window;
	function get_window() return @:privateAccess getScene().window;
	var mouseX(get,never) : Float;
	function get_mouseX() return @:privateAccess getScene().events.mouseX;
	var mouseY(get,never) : Float;
	function get_mouseY() return @:privateAccess getScene().events.mouseY;
	var mouseLock(get, set) : Bool;
	function get_mouseLock() return @:privateAccess window.mouseMode != Absolute;
	function set_mouseLock(v : Bool) {
		@:privateAccess window.mouseMode = v ? AbsoluteUnbound(true) : Absolute;
		return v;
	}

	var gizmo: h3d.scene.Object;
	var scaleRot : h3d.Matrix;
	var updateFunc: Float -> Void;
	var rotateAxisShader : RotateAxisShader = new RotateAxisShader();
	var moving : Bool;
	var initialAbsPos : h3d.Matrix;
	var initialRay : h3d.col.Ray;
	var initialMousePos : h2d.col.Point;

	public function new(parent: h3d.scene.Object) {
		super(parent);
		gizmo = loadGizmoModel();
		addChild(gizmo);
		translationMode();
	}

	public function update(dt : Float) {
		var cam = this.getScene().camera;
		var abs = gizmo.getAbsPos();
		var gpos = abs.getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		if (hxd.Math.isNaN(distToCam))
			distToCam = 1000000000.0;
		var engine = h3d.Engine.getCurrent();
		var ratio = 250 / engine.height;
		var scale = ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0);
		if (cam.orthoBounds != null) {
			scale = ratio * (cam.orthoBounds.xSize) * 0.5;
		}

		gizmo.setScale(scale);

		if (updateFunc != null)
			updateFunc(dt);
	}


	public function moveToObjects(objs : Array<h3d.scene.Object>) {
		var invDefMat = new h3d.Matrix();
		invDefMat.identity();
		if (objs[0].defaultTransform != null)
			invDefMat = objs[0].defaultTransform?.getInverse();
		var euler = invDefMat.multiplied(objs[0].getAbsPos()).getEulerAngles();

		scaleRot = new h3d.Matrix();
		scaleRot.identity();
		if (!isLocalTransform){
			scaleRot.initRotation(euler.x, euler.y, euler.z);
			scaleRot.invert();
		}

		if (isLocalTransform && objs.length == 1)
			setRotation(euler.x, euler.y, euler.z);
		else
			setRotation(0,0,0);

		// Find centroid of objects
		var centroid = new h3d.col.Point(0, 0, 0);
		for (o in objs) {
			var p = o.getAbsPos().getPosition();
			centroid.x += p.x;
			centroid.y += p.y;
			centroid.z += p.z;
		}
		centroid.x /= objs.length;
		centroid.y /= objs.length;
		centroid.z /= objs.length;

		setPosition(centroid.x, centroid.y, centroid.z);
	}

	public function isGizmo(obj : h3d.scene.Object) {
		return gizmo.findAll((f) -> f).contains(obj);
	}


	public function switchMode() {
		switch (mode) {
			case Translation:
				rotationMode();
			case Rotation:
				scalingMode();
			case Scale:
				translationMode();
			case Full:
		}
	}

	public function translationMode() {
		for (o in gizmo.getMeshes()) {
			if (o.name == null) continue;
			var visible = o.name.indexOf("_Translate") >= 0
			|| o.name.indexOf("_Branch") >= 0
			|| o.name.indexOf("_Plane") >= 0;
			o.visible = visible;
		}

		mode = Translation;
		onChangeMode(mode);
	}

	public function rotationMode() {
		for (o in gizmo.getMeshes()) {
			var visible = o.name.indexOf("_Rotate") >= 0;
			o.visible = visible;
		}

		mode = Rotation;
		onChangeMode(mode);
	}

	public function scalingMode() {
		for (o in gizmo.getMeshes()) {
			var visible = o.name.indexOf("_Scale") >= 0
			|| o.name.indexOf("_Branch") >= 0
			|| o.name.indexOf("_Plane") >= 0;
			o.visible = visible;
		}
		mode = Scale;
		onChangeMode(mode);
	}


	function startMove(handle: Handle, duplicating: Bool = false) {
		if (onStartMove != null && !moving) {
			initialAbsPos = this.getAbsPos().clone();
			onStartMove(handle);

			initialMousePos = new h2d.col.Point(mouseX, mouseY);
			var scene = getScene();
			initialRay = scene.camera.rayFromScreen(mouseX, mouseY, scene.scenePosition?.width ?? -1, scene.scenePosition?.height ?? -1);
		}

		moving = true;
	}

	function move(handle: Handle) {
		if (onMove != null) {
			var initialPosition = initialAbsPos.getPosition();
			var initialScale = initialAbsPos.getScale();
			var initialRotation = new h3d.Quat();
			initialRotation.initRotateMatrix(initialAbsPos);
			var scene = getScene();
			var ray = scene.camera.rayFromScreen(mouseX, mouseY, scene.scenePosition?.width ?? -1, scene.scenePosition?.height ?? -1);
			var dragPlane = h3d.col.Plane.fromNormalPoint(switch(handle) {
				case XYPlane, XArrow, YArrow: mode == Scale ? scaleRot.up() : initialAbsPos.up();
				case XZPlane: mode == Scale ? scaleRot.right() : initialAbsPos.right();
				case YZPlane, ZArrow: mode == Scale ? scaleRot.front() : initialAbsPos.front();
				default: initialRay.getDir();
			}, initialPosition);

			var deltaPosition : h3d.col.Point = null;
			var deltaRotation : h3d.Quat = null;
			var deltaScale : h3d.Vector = null;

			var delta = ray.intersect(dragPlane) - initialRay.intersect(dragPlane);
			var axis = switch (handle) {
				case XArrow, XRing:
					mode == Scale ? scaleRot.front() : initialAbsPos.front();
				case YArrow, YRing:
					mode == Scale ? scaleRot.right() : initialAbsPos.right();
				case ZArrow, ZRing:
					mode == Scale ? scaleRot.up() : initialAbsPos.up();
				default:
					null;
			}

			switch (mode) {
				case Full:
				case Translation:
					if (axis != null)
						delta = delta.dot(axis) * axis;
					deltaPosition = new h3d.Vector(snap(delta.x, mode), snap(delta.y, mode), snap(delta.z, mode));
					setPosition(initialPosition.x + deltaPosition.x, initialPosition.y + deltaPosition.y, initialPosition.z + deltaPosition.z);
				case Rotation:
					var v1 = initialPosition.sub(initialRay.intersect(dragPlane)).normalized();
					var v2 = initialPosition.sub(ray.intersect(dragPlane)).normalized();
					var angle = snap(Math.atan2(v1.cross(v2).dot(axis), v1.dot(v2)), Rotation);
					deltaRotation = new h3d.Quat();
					deltaRotation.initRotateAxis(axis.x, axis.y, axis.z, angle);
					var localQuat = new h3d.Quat();
					localQuat.multiply(deltaRotation, initialRotation);
					setRotationQuat(localQuat);
				case Scale:
					if (handle == Center) {
						var v = new h2d.col.Point(mouseX, mouseY) - initialMousePos;
						v.y *= -1;
						v.normalize();
						var d = new h2d.col.Point(1, 1);
						d.normalize();

						var f = d.dot(v);
						var margin = 0.4;
						f = f < margin && f > -margin ? f / margin : f < 0 ? -1 : 1;

						var s = snap((delta.length() * f * 0.5) + 1, mode);
						deltaScale = new h3d.Vector(s, s, s);
					}
					else {
						if (axis != null)
							delta = delta.dot(axis) * axis;
						deltaScale = new h3d.Vector(snap((delta.x * 0.5) + 1, mode), snap((delta.y * 0.5) + 1, mode), snap((delta.z * 0.5) + 1, mode));
					}

			}

			onMove(deltaPosition, deltaRotation, deltaScale);
		}

		if (K.isPressed(K.ESCAPE) || !K.isDown(K.MOUSE_LEFT)) {
			finishMove(handle);
		}
	}

	function finishMove(handle: Handle) {
		mouseLock = false;
		updateFunc = null;
		if(onFinishMove != null)
			onFinishMove();
		posChanged = true;
		moving = false;
	}


	function loadGizmoModel() : h3d.scene.Object {
		var engine = h3d.Engine.getCurrent();
		@:privateAccess var model : hxd.fmt.hmd.Library = engine.resCache.get(Gizmo);
		if (model == null) {
			model = hxd.res.Embed.getResource("hrt/tools/res/gizmo.hmd").toModel().toHmd();
			@:privateAccess engine.resCache.set(Gizmo, model);
		}

		gizmo = model.makeObject();

		for (o in gizmo.getMeshes()) {
			var axis = o.name.indexOf("_X_") >= 0 ? 0 : o.name.indexOf("_Y_") >= 0 ? 1 : o.name.indexOf("_Z_") >= 0 ? 2 : -1;
			var isPlane = o.name.indexOf("Plane") >= 0;

			var mat = o.getMaterials()[0];
			mat.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
			mat.mainPass.blend(SrcAlpha, OneMinusSrcAlpha);
			mat.mainPass.culling = None;
			mat.mainPass.depth(true, Always);
			mat.mainPass.setPassName("ui");
			if (o.name.indexOf("Rotate") >= 0)
				mat.mainPass.addShader(rotateAxisShader);
			var color = (switch (axis) {
				case 0: X_COLOR;
				case 1: Y_COLOR;
				case 2: Z_COLOR;
				case _: DEFAULT_COLOR;
			});
			mat.color.setColor(color);

			var highlight = hxd.Math.colorLerp(color, 0xffffff, 0.3);
			var interactive = new h3d.scene.Interactive(getHandleCollider(o), o);
			interactive.priority = o.name.indexOf("Full_Scale") >= 0 ? 101 : 100;
			interactive.onOver = function(e : hxd.Event) {
				e.propagate = false;
				mat.color.setColor(highlight);
				mat.color.w = 1.0;
			}
			interactive.onOut = function(e : hxd.Event) {
				e.propagate = false;
				mat.color.setColor(color);
			}
			interactive.onPush = function(e) {
				e.propagate = false;
				var startPt = new h2d.col.Point(mouseX, mouseY);
				updateFunc = function(dt) {
					var mousePt = new h2d.col.Point(mouseX, mouseY);
					if (mousePt.distance(startPt) > 5) {
						var handle : Handle = null;
						if (axis == 0)
							handle = mode == Rotation ? XRing : isPlane ? YZPlane : XArrow;
						else if (axis == 1)
							handle = mode == Rotation ? YRing : isPlane ? XZPlane : YArrow;
						else if (axis == 2)
							handle = mode == Rotation ? ZRing : isPlane ? XYPlane : ZArrow;
						else
							handle = Center;
						if (!moving)
							startMove(handle);
						else
							move(handle);
					}
				}
				e.propagate = false;
			}
		}

		var p = new h3d.prim.Sphere(0.8, 25, 25);
		p.addNormals();

		var m = new h3d.scene.Mesh(p, null, gizmo);
		m.name = "Sphere_Rotate";
		for (mat in m.getMaterials()) {
			mat.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
			mat.mainPass.culling = None;
			mat.mainPass.depth(true, Always);
			mat.mainPass.addShader(new RotateSphereShader());
			mat.mainPass.setPassName("ui");
			mat.color = new h3d.Vector4(1, 1, 1, 1);
			mat.blendMode = Alpha;
		}

		return gizmo;
	}

	function getHandleCollider(obj: h3d.scene.Mesh) : h3d.col.Collider {
		if (obj.name.indexOf("_Plane") >= 0 || obj.name.indexOf("_Translate") >= 0 || obj.name.indexOf("_Scale") >= 0) {
			var bounds = obj.primitive.getBounds();
			var pos = bounds.getCenter();
			var sphere = new h3d.col.Sphere(pos.x, pos.y, pos.z, (bounds.getSize().length() / 2) * 1.2);
			return sphere;
		}

		return obj.primitive.getCollider();
	}


	public dynamic function snap(v: Float, mode: EditMode) : Float {
		return v;
	}

	public dynamic function shoudSnapOnGrid() : Bool {
		return false;
	}

	public dynamic function onChangeMode(mode : EditMode) {}
}