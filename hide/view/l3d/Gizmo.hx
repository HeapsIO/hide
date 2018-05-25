package hide.view.l3d;
import hxd.Math;
import hxd.Key as K;

typedef AxesOptions = {
	?x: Bool,
	?y: Bool,
	?z: Bool
}

enum TransformMode {
	MoveX;
	MoveY;
	MoveZ;
	MoveXY;
	MoveYZ;
	MoveZX;
	RotateX;
	RotateY;
	RotateZ;
	Scale;
}

class Gizmo extends h3d.scene.Object {

	var gizmo: h3d.scene.Object;
	var scene : hide.comp.Scene;
	var updateFunc: Float -> Void;

	public var onStartMove: TransformMode -> Void;
	public var onMove: h3d.Vector -> h3d.Quat -> h3d.Vector -> Void;
	public var onFinishMove: Void -> Void;
	public var moving(default, null): Bool;

	public var moveStep = 0.5;
	public var rotateStep = 10.0 * Math.PI / 180.0;

	var debug: h3d.scene.Graphics;
	var axisScale = false;
	var snapGround = false;
	var intOverlay : h2d.Interactive;

	public function new(scene: hide.comp.Scene) {
		super(scene.s3d);
		this.scene = scene;
		var path = hide.Ide.inst.appPath + "/res/gizmo.hmd";
		var data = sys.io.File.getBytes(path);
		var hmd = hxd.res.Any.fromBytes(path, data).toModel().toHmd();
		gizmo = hmd.makeObject();
		addChild(gizmo);
		debug = new h3d.scene.Graphics(scene.s3d);

		function setup(objname, color, mode: TransformMode) {
			var o = gizmo.getObjectByName(objname);
			var hit = gizmo.getObjectByName(objname + "_hit");
			if(hit == null) {
				hit = o;
			}
			else {
				hit.visible = false;
			}
			var mat = o.getMaterials()[0];
			mat.mainPass.setPassName("ui");
			mat.mainPass.depth(true, Always);
			mat.blendMode = Alpha;
			var mesh = hit.getMeshes()[0];
			var interactive = new h3d.scene.Interactive(mesh.primitive.getCollider(), o);
			interactive.priority = 100;
			var highlight = hxd.Math.colorLerp(color, 0xffffffff, 0.1);
			color = hxd.Math.colorLerp(color, 0xff000000, 0.2);
			mat.color.setColor(color);
			interactive.onOver = function(e : hxd.Event) {
				mat.color.setColor(highlight);
				mat.color.w = 1.0;
			}
			interactive.onOut = function(e : hxd.Event) {
				mat.color.setColor(color);
			}
			interactive.onPush = function(e) {
				var startPt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
				updateFunc = function(dt) {
					var mousePt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
					if(mousePt.distance(startPt) > 5) {
						startMove(mode);
					}
				}
			}
			interactive.onRelease = function(e) {
				if(moving)
					finishMove();
				else
					updateFunc = null;
			}
		}

		setup("xAxis", 0x90ff0000, MoveX);
		setup("yAxis", 0x9000ff00, MoveY);
		setup("zAxis", 0x900000ff, MoveZ);
		setup("xy", 0x90ffff00, MoveXY);
		setup("xz", 0x90ffff00, MoveZX);
		setup("yz", 0x90ffff00, MoveYZ);
		setup("xRotate", 0x90ff0000, RotateX);
		setup("yRotate", 0x9000ff00, RotateY);
		setup("zRotate", 0x900000ff, RotateZ);
		setup("scale", 0x90ffffff, Scale);
	}

	public function startMove(mode: TransformMode, ?duplicating=false) {
		moving = true;
		if(onStartMove != null) onStartMove(mode);
		var startMat = getAbsPos().clone();
		var startPos = getAbsPos().pos().toPoint();
		var dragPlane = null;
		var cam = scene.s3d.camera;
		var norm = startPos.sub(cam.pos.toPoint());
		intOverlay = new h2d.Interactive(40000, 40000, scene.s2d);
		intOverlay.onPush = function(e) finishMove();
		switch(mode) {
			case MoveX: norm.x = 0;
			case MoveY: norm.y = 0;
			case MoveZ: norm.z = 0;
			case MoveXY: norm.set(0, 0, 1);
			case MoveYZ: norm.set(1, 0, 0);
			case MoveZX: norm.set(0, 1, 0);
			case RotateX: norm.set(1, 0, 0);
			case RotateY: norm.set(0, 1, 0);
			case RotateZ: norm.set(0, 0, 1);
			case Scale: norm.z = 0;
		}
		norm.normalize();
		dragPlane = h3d.col.Plane.fromNormalPoint(norm, startPos);
		var startDragPt = getDragPoint(dragPlane);
		updateFunc = function(dt) {
			var curPt = getDragPoint(dragPlane);
			var delta = curPt.sub(startDragPt);
			var vec = new h3d.Vector(0,0,0);
			var quat = new h3d.Quat();
			var speedFactor = K.isDown(K.SHIFT) ? 0.1 : 1.0;
			delta.scale(speedFactor);

			inline function scaleFunc(x: Float) {
				return x > 0 ? (x + 1) : 1 / (1 - x);
			}

			function snap(m: Float) {
				if(moveStep <= 0 || !K.isDown(K.CTRL))
					return m;

				var step = K.isDown(K.SHIFT) ? moveStep / 2.0 : moveStep;
				return hxd.Math.round(m / step) * step;
			}

			if(axisScale) {
				if(mode == MoveX) vec.x = snap(delta.dot(startMat.front().toPoint()));
				if(mode == MoveY) vec.y = snap(delta.dot(startMat.right().toPoint()));
				if(mode == MoveZ) vec.z = snap(delta.dot(startMat.up().toPoint()));
			}
			else {
				if(mode == MoveX || mode == MoveXY || mode == MoveZX) vec.x = snap(delta.x);
				if(mode == MoveY || mode == MoveYZ || mode == MoveXY) vec.y = snap(delta.y);
				if(mode == MoveZ || mode == MoveZX || mode == MoveYZ) vec.z = snap(delta.z);

				x = (startPos.x + vec.x);
				y = (startPos.y + vec.y);
				z = (startPos.z + vec.z);
			}

			if(mode == Scale) {
				var scale = scaleFunc(delta.z * 0.5);
				vec.set(scale, scale, scale);
			}

			if(mode == RotateX || mode == RotateY || mode == RotateZ) {
				var v1 = startDragPt.sub(startPos);
				v1.normalize();
				var v2 = curPt.sub(startPos);
				v2.normalize();

				var angle = Math.atan2(v1.cross(v2).dot(norm), v1.dot(v2)) * speedFactor;
				if(rotateStep > 0 && K.isDown(K.CTRL))
					angle =  hxd.Math.round(angle / rotateStep) * rotateStep;
				quat.initRotateAxis(norm.x, norm.y, norm.z, angle);
				setRotationQuat(quat);
			}

			if(onMove != null) {
				if(axisScale) {
					vec.x = scaleFunc(vec.x);
					vec.y = scaleFunc(vec.y);
					vec.z = scaleFunc(vec.z);
					onMove(null, null, vec);
				}
				else {
					if(mode == Scale)
						onMove(null, null, vec);
					else
						onMove(vec, quat, null);
				}
			}

			if(duplicating && K.isPressed(K.MOUSE_LEFT) || K.isPressed(K.ESCAPE) || (!duplicating && !K.isDown(K.MOUSE_LEFT))) {
				finishMove();
			}
		}
	}

	function finishMove() {
		updateFunc = null;
		if(onFinishMove != null)
			onFinishMove();
		getRotationQuat().identity();
		posChanged = true;
		moving = false;
		if(intOverlay != null) {
			intOverlay.remove();
			intOverlay = null;
		}
	}

	function getDragPoint(plane: h3d.col.Plane) {
		var cam = scene.s3d.camera;
		var ray = cam.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);
		return ray.intersect(plane);
	}

	public function update(dt) {
		var cam = this.getScene().camera;
		var gpos = gizmo.getAbsPos().pos();
		var distToCam = cam.pos.sub(gpos).length();
		gizmo.setScale(distToCam / 30 );

		axisScale = K.isDown(K.ALT);
		for(n in ["xRotate", "yRotate", "zRotate", "xy", "xz", "yz", "scale"]) {
			gizmo.getObjectByName(n).visible = !axisScale;
		}

		if(updateFunc != null) {
			updateFunc(dt);
		}
	}
}