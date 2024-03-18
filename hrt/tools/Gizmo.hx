package hrt.tools;
import h3d.scene.Object;
import hxd.Math;
import hxd.Key as K;

typedef AxesOptions = {
	?x: Bool,
	?y: Bool,
	?z: Bool
}

enum EditMode {
	Translation;
	Rotation;
	Scaling;
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

class ChangingStepViewer extends h3d.scene.Object {
	var textObject : h2d.ObjectFollower;
	var lifeTime : Float = 1.3;
	var life : Float = 0.;
	var text : h2d.Text;

	public function new( parentGizmo : Gizmo, stepText : String ) {
		super(parentGizmo);
		name = "ChangingStepViewer";
		textObject = new h2d.ObjectFollower(parentGizmo, @:privateAccess parentGizmo.root2d);

		text = new h2d.Text(hxd.res.DefaultFont.get(), textObject);
		text.textAlign = Center;
		text.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		text.setScale(2);
		text.setPosition(text.x + 100, text.y);
		text.text = stepText;
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		var dt = hxd.Timer.tmod * 1. / 60;
		life += dt;
		textObject.alpha = 1-life/lifeTime;
		text.y -= 20*dt*life/lifeTime;
		if (life >= lifeTime) {
			textObject.remove();
			remove();
		}
		super.sync(ctx);
	}
}

class Gizmo extends h3d.scene.Object {

	static var GIZMO_COLORS = {
		x : 0xff0000,
		y : 0x00ff00,
		z : 0x0000ff,
		scale : 0xffffff,
		multiAxes : 0xffff00
	}

	var gizmo: h3d.scene.Object;
	var objects: Array<h3d.scene.Object>;
	var deltaTextObject : h2d.ObjectFollower;
	var root2d : h2d.Object;
	var updateFunc: Float -> Void;
	var mouseX(get,never) : Float;
	var mouseY(get,never) : Float;
	var mouseLock(get, set) : Bool;
	var window(get, never) : hxd.Window;
	var xFollow : h2d.ObjectFollower;
	var yFollow : h2d.ObjectFollower;
	var zFollow : h2d.ObjectFollower;
	var xLabel : h2d.Text;
	var yLabel : h2d.Text;
	var zLabel : h2d.Text;

	public var onStartMove: TransformMode -> Void;
	public var onMove: h3d.Vector -> h3d.Quat -> h3d.Vector -> Void;
	public var onFinishMove: Void -> Void;
	public var moving(default, null): Bool;
	dynamic public function snap(v: Float, mode: EditMode) : Float {
		return v;
	}
	dynamic public function shoudSnapOnGrid() : Bool {
		return false;
	}

	public var editMode : EditMode = Translation;

	var debug: h3d.scene.Graphics;
	var axisScale = false;
	var snapGround = false;
	var intOverlay : h2d.Interactive;
	var mainGizmosVisible : Bool = true;

	public function new(parent:h3d.scene.Object, root2d: h2d.Object) {
		super(parent);
		this.root2d=root2d;
		gizmo = loadGizmoModel();
		addChild(gizmo);
		debug = new h3d.scene.Graphics(this);

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
			mat.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
			mat.mainPass.blend(SrcAlpha, OneMinusSrcAlpha);
			mat.mainPass.depth(false, Always);
			mat.mainPass.setPassName("ui");
			var mesh = hit.getMeshes()[0];
			var interactive = new h3d.scene.Interactive(mesh.primitive.getCollider(), o);
			interactive.priority = 100;
			var highlight = hxd.Math.colorLerp(color, 0xffffff, 0.1);
			color = hxd.Math.colorLerp(color, 0x000000, 0.2);
			color = (color & 0x00ffffff) | 0x80000000;
			mat.color.setColor(color);
			interactive.onOver = function(e : hxd.Event) {
				mat.color.setColor(highlight);
				mat.color.w = 1.0;
			}
			interactive.onOut = function(e : hxd.Event) {
				mat.color.setColor(color);

				if (!mainGizmosVisible)
					mat.color.w = 0;
			}
			interactive.onPush = function(e) {
				var startPt = new h2d.col.Point(mouseX, mouseY);
				updateFunc = function(dt) {
					var mousePt = new h2d.col.Point(mouseX, mouseY);
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

			objects.push(o);
		}

		objects = [];

		setup("xAxis", GIZMO_COLORS.x, MoveX);
		setup("yAxis", GIZMO_COLORS.y, MoveY);
		setup("zAxis", GIZMO_COLORS.z, MoveZ);
		setup("xy", GIZMO_COLORS.multiAxes, MoveXY);
		setup("xz", GIZMO_COLORS.multiAxes, MoveZX);
		setup("yz", GIZMO_COLORS.multiAxes, MoveYZ);
		setup("xRotate", GIZMO_COLORS.x, RotateX);
		setup("yRotate", GIZMO_COLORS.y, RotateY);
		setup("zRotate", GIZMO_COLORS.z, RotateZ);
		setup("scale", GIZMO_COLORS.scale, Scale);
		setup("xScale", GIZMO_COLORS.x, MoveX);
		setup("yScale", GIZMO_COLORS.y, MoveY);
		setup("zScale", GIZMO_COLORS.z, MoveZ);

		/*xFollow = new h2d.ObjectFollower(this, root2d);
		yFollow = new h2d.ObjectFollower(this, root2d);
		zFollow = new h2d.ObjectFollower(this, root2d);

		xLabel = new h2d.Text(hxd.res.DefaultFont.get(), xFollow);
		xLabel.text = "X";
		xLabel.textColor = GIZMO_COLORS.x;
		xLabel.textAlign = Center;
		xLabel.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		xLabel.setScale(1.2);

		yLabel = new h2d.Text(hxd.res.DefaultFont.get(), yFollow);
		yLabel.text = "Y";
		yLabel.textColor = GIZMO_COLORS.y;
		yLabel.textAlign = Center;
		yLabel.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		yLabel.setScale(1.2);

		zLabel = new h2d.Text(hxd.res.DefaultFont.get(), zFollow);
		zLabel.text = "Z";
		zLabel.textColor = GIZMO_COLORS.z;
		zLabel.textAlign = Center;
		zLabel.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		zLabel.setScale(1.2);*/

		translationMode();
	}

	public function loadGizmoModel() : h3d.scene.Object {
		var engine = h3d.Engine.getCurrent();
		@:privateAccess var model : hxd.fmt.hmd.Library = engine.resCache.get(Gizmo);
		if (model == null) {
			model = hxd.res.Embed.getResource("hrt/tools/res/gizmo.hmd").toModel().toHmd();
			@:privateAccess engine.resCache.set(Gizmo, model);
		}
		return model.makeObject();
	}

	public dynamic function onChangeMode(mode : EditMode) {}

	public function translationMode() {
		editMode = Translation;
		axisScale = false;
		for(n in ["xAxis", "yAxis", "zAxis", "xy", "xz", "yz"]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xRotate", "yRotate", "zRotate", "scale", "xScale", "yScale", "zScale"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function rotationMode() {
		editMode = Rotation;
		axisScale = false;
		for(n in ["xRotate", "yRotate", "zRotate", ]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xAxis", "yAxis", "zAxis", "xy", "xz", "yz", "scale", "xScale", "yScale", "zScale"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function scalingMode() {
		editMode = Scaling;
		axisScale = true;
		for(n in ["scale", "xScale", "yScale", "zScale"]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xAxis", "yAxis", "zAxis","xRotate", "yRotate", "zRotate", "xy", "xz", "yz"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function startMove(mode: TransformMode, ?duplicating=false) {
		if (mode == Scale || (axisScale && (mode == MoveX || mode == MoveY || mode == MoveZ)))
			mouseLock = true;
		moving = true;
		if(onStartMove != null) onStartMove(mode);
		var startMat = getAbsPos().clone();
		var startQuat = new h3d.Quat();
		startQuat.initRotateMatrix(startMat);
		var startPos = getAbsPos().getPosition().toPoint();
		var dragPlane = null;
		var cam = getScene().camera;
		var norm = startPos.sub(cam.pos.toPoint());
		intOverlay = new h2d.Interactive(40000, 40000, root2d);
		intOverlay.onPush = function(e) finishMove();
		switch(mode) {
			case MoveXY: norm.set(0, 0, 1);
			case MoveYZ: norm.set(1, 0, 0);
			case MoveZX: norm.set(0, 1, 0);
			case RotateX: norm.set(1, 0, 0);
			case RotateY: norm.set(0, 1, 0);
			case RotateZ: norm.set(0, 0, 1);
			default:
		}

		if (mode == MoveX || mode == MoveY || mode == MoveZ || mode == Scale) {
			var point = getScene().camera.rayFromScreen(mouseX, mouseY).getDir();
			dragPlane = h3d.col.Plane.fromNormalPoint(point, startPos);
		} else {
			norm.normalize();
			norm.transform3x3(startMat);
			dragPlane = h3d.col.Plane.fromNormalPoint(norm, startPos);
		}
		var startDragPt = getDragPoint(dragPlane);
		var cursor = new h3d.scene.Object();
		deltaTextObject = new h2d.ObjectFollower(cursor, root2d);

		var tx = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		tx.textColor = GIZMO_COLORS.x;
		tx.textAlign = Center;
		tx.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		tx.setScale(1.2);
		var ty = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		ty.textColor = GIZMO_COLORS.y;
		ty.textAlign = Center;
		ty.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		ty.setScale(1.2);
		var tz = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		tz.textColor = GIZMO_COLORS.z;
		tz.textAlign = Center;
		tz.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		tz.setScale(1.2);
		updateFunc = function(dt) {
			tx.visible = false;
			ty.visible = false;
			tz.visible = false;
			var curPt = getDragPoint(dragPlane);
			tx.setPosition(mouseX + 32, mouseY - 15);
			ty.setPosition(mouseX + 32, mouseY);
			tz.setPosition(mouseX + 32, mouseY + 15);
			var delta = curPt.sub(startDragPt);
			var vec = new h3d.Vector(0,0,0);
			var quat = new h3d.Quat();
			var speedFactor = (K.isDown(K.SHIFT) && !K.isDown(K.CTRL)) ? 0.1 : 1.0;
			delta.scale(speedFactor);
			inline function scaleFunc(x: Float) {
				return x > 0 ? x + 1 : 1 / (1 - x);
			}

			function moveSnap(m: Float) {
				return m;
				/*if(moveStep <= 0 || !scene.editor.getSnapStatus() || axisScale)
					return m;

				var step = K.isDown(K.SHIFT) ? moveStep / 2.0 : moveStep;
				return hxd.Math.round(m / step) * step;*/
			}

			var isMove = (mode == MoveX || mode == MoveY || mode == MoveZ || mode == MoveXY || mode == MoveYZ || mode == MoveZX);

			if(mode == MoveX || mode == MoveXY || mode == MoveZX) vec.x = snap(delta.dot(startMat.front().toPoint()),Translation);
			if(mode == MoveY || mode == MoveYZ || mode == MoveXY) vec.y = snap(delta.dot(startMat.right().toPoint()),Translation);
			if(mode == MoveZ || mode == MoveZX || mode == MoveYZ) vec.z = snap(delta.dot(startMat.up().toPoint()),Translation);

			if(!axisScale) {
				vec.transform3x3(startMat);
				if (vec.x != 0) {
					tx.visible = true;
					tx.text = "X : "+ Math.round(vec.x*100)/100.;
				}
				if (vec.y != 0) {
					ty.visible = true;
					ty.text = "Y : "+ Math.round(vec.y*100)/100.;
				}
				if (vec.z != 0) {
					tz.visible = true;
					tz.text = "Z : "+ Math.round(vec.z*100)/100.;
				}
				x = startPos.x + vec.x;
				y = startPos.y + vec.y;
				z = startPos.z + vec.z;
				if (shoudSnapOnGrid() && isMove) {
					x = snap(x, Translation);
					y = snap(y, Translation);
					z = snap(z, Translation);
				}
			}

			if(mode == Scale) {
				var scale = snap(scaleFunc(delta.z * 0.5), Scaling);
				vec.set(scale, scale, scale);
			}

			var doRot = false;
			if(mode == RotateX || mode == RotateY || mode == RotateZ) {
				doRot = true;
				var v1 = startDragPt.sub(startPos);
				v1.normalize();
				var v2 = curPt.sub(startPos);
				v2.normalize();

				var angle = snap(Math.radToDeg(Math.atan2(v1.cross(v2).dot(norm), v1.dot(v2)) * speedFactor), Rotation);
				angle = Math.degToRad(angle);

				if (mode == RotateX && angle != 0) {
					tx.visible = true;
					tx.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				if (mode == RotateY && angle != 0) {
					ty.visible = true;
					ty.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				if (mode == RotateZ && angle != 0) {
					tz.visible = true;
					tz.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				quat.initRotateAxis(norm.x, norm.y, norm.z, angle);
				var localQuat = new h3d.Quat();
				localQuat.multiply(quat, startQuat);
				setRotationQuat(localQuat);
			}

			if(onMove != null) {
				if(axisScale && mode != Scale) {
					vec.x = snap(scaleFunc(vec.x), Scaling);
					vec.y = snap(scaleFunc(vec.y), Scaling);
					vec.z = snap(scaleFunc(vec.z), Scaling);
					if (vec.x != 1) {
						tx.visible = true;
						tx.text = ""+ Math.round(vec.x*100)/100.;
					}
					if (vec.y != 1) {
						ty.visible = true;
						ty.text = ""+ Math.round(vec.y*100)/100.;
					}
					if (vec.z != 1) {
						tz.visible = true;
						tz.text = ""+ Math.round(vec.z*100)/100.;
					}
					onMove(null, null, vec);
				}
				else {
					if(mode == Scale) {
						if (vec.x != 1) {
							tx.visible = true;
							tx.text = ""+ Math.round(vec.x*100)/100.;
						}
						if (vec.y != 1) {
							ty.visible = true;
							ty.text = ""+ Math.round(vec.y*100)/100.;
						}
						if (vec.z != 1) {
							tz.visible = true;
							tz.text = ""+ Math.round(vec.z*100)/100.;
						}
						onMove(null, null, vec);
					}
					else if (doRot) {
						onMove(null, quat, null);
					}
					else {
						onMove(vec, null, null);
					}
				}
			}

			if(duplicating && K.isPressed(K.MOUSE_LEFT) || K.isPressed(K.ESCAPE) || (!duplicating && !K.isDown(K.MOUSE_LEFT))) {
				finishMove();
			}
		}
	}

	function get_mouseX() return @:privateAccess window.mouseX;
	function get_mouseY() return @:privateAccess window.mouseY;
	function get_window() return @:privateAccess getScene().window;
	function get_mouseLock() return @:privateAccess window.mouseMode != Absolute;
	function set_mouseLock(v : Bool) {
		@:privateAccess window.mouseMode = v ? AbsoluteUnbound(true) : Absolute;
		return v;
	}

	function finishMove() {
		deltaTextObject.remove();
		mouseLock = false;
		updateFunc = null;
		if(onFinishMove != null)
			onFinishMove();
		posChanged = true;
		moving = false;
		if(intOverlay != null) {
			intOverlay.remove();
			intOverlay = null;
		}
	}

	function getDragPoint(plane: h3d.col.Plane) {
		var cam = getScene().camera;
		var ray = cam.rayFromScreen(mouseX, mouseY);
		return ray.intersect(plane);
	}

	public function updateLocal(dt) {
		update(dt, true);
	}

	static var tempMatrix = new h3d.Matrix();
	public function update(dt, isLocal:Bool) {
		var cam = this.getScene().camera;
		var abs = gizmo.getAbsPos();
		var gpos = abs.getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		if (hxd.Math.isNaN(distToCam)) {
			distToCam = 1000000000.0;
		}
		var engine = h3d.Engine.getCurrent();
		var ratio = 150 / engine.height;
		var scale = ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0);
		if (cam.orthoBounds != null) {
			scale = ratio *  (cam.orthoBounds.xSize) * 0.5;
		}
		gizmo.setScale(scale);

		if( !moving ) {
			var dir = cam.pos.sub(gpos).toPoint();
			if (isLocal || this.editMode == Scaling)
			{
				var rot = getRotationQuat().toMatrix(tempMatrix);
				rot.invert();
				dir.transform3x3(rot);
			}

			var scale = 1.5 * gizmo.absPos.getScale();

			gizmo.getObjectByName("xAxis").setRotation(0, 0, dir.x < 0 ? Math.PI : 0);
			// xFollow.offsetX = dir.x < 0 ? -scale.x : scale.x;
			// xLabel.text = dir.x < 0 ? '-X' : 'X';
			// xFollow.offsetZ = 0.09 * scale.x; // Center the text

			gizmo.getObjectByName("yAxis").setRotation(0, 0, dir.y < 0 ? Math.PI : 0);
			// yFollow.offsetY = dir.y < 0 ? -scale.y : scale.y;
			// yLabel.text = dir.y < 0 ? '-Y' : 'Y';
			// yFollow.offsetZ = 0.09 * scale.y; // Center the text

			gizmo.getObjectByName("zAxis").setRotation(dir.z < 0 ? Math.PI : 0, 0, 0);
			// zFollow.offsetZ = dir.z < 0 ? -scale.z : scale.z;
			// zFollow.offsetZ += 0.09 * scale.z; // Center the text
			// zLabel.text = dir.z < 0 ? '-Z' : 'Z';

			var zrot = dir.x < 0 ? dir.y < 0 ? Math.PI : Math.PI / 2.0 : dir.y < 0 ? -Math.PI / 2.0 : 0;

			gizmo.getObjectByName("xy").setRotation(0, 0, zrot);
			gizmo.getObjectByName("xz").setRotation(0, dir.z < 0 ? Math.PI : 0, dir.x < 0 ? Math.PI : 0);
			gizmo.getObjectByName("yz").setRotation(dir.z < 0 ? Math.PI : 0, 0, dir.y < 0 ? Math.PI : 0);

			gizmo.getObjectByName("zRotate").setRotation(0, 0, zrot);
			gizmo.getObjectByName("yRotate").setRotation(0, dir.z < 0 ? Math.PI : 0, dir.x < 0 ? Math.PI : 0);
			gizmo.getObjectByName("xRotate").setRotation(dir.z < 0 ? Math.PI : 0, 0, dir.y < 0 ? Math.PI : 0);
		}

		var labelVisible = editMode == EditMode.Translation && this.visible && !moving;
		//xLabel.visible = yLabel.visible = zLabel.visible = labelVisible;

		//axisScale = K.isDown(K.ALT);
		// for(n in ["xRotate", "yRotate", "zRotate", "xy", "xz", "yz", "scale"]) {
		// 	gizmo.getObjectByName(n).visible = !axisScale;
		// }

		if(updateFunc != null) {
			updateFunc(dt);
		}
	}

	public function toggleGizmosVisiblity(show : Bool) {
		mainGizmosVisible = show;

		for (o in objects)
			o.getMaterials()[0].color.w = show ? 0.2 : 0;

	}
}