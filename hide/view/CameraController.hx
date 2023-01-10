package hide.view;

import hxd.Math;
import hxd.Key as K;

class CameraControllerBase extends h3d.scene.CameraController {
	var sceneEditor : hide.comp.SceneEditor;

	public function new(parent, sceneEditor) {
		super(null, parent);
		this.sceneEditor = sceneEditor;
	}

	public var wantedFOV = 90.0;
	public var camSpeed = 1.0;

	public function loadSettings(data : Dynamic) : Void {
		wantedFOV = data.fov != null ? data.fov : 60.0;
		sceneEditor.scene.s3d.camera.fovY = wantedFOV;
	}

	public function saveSettings(data : Dynamic) : Void {
		
	}
}

class CamController extends CameraControllerBase {
	public var groundSnapAngle = hxd.Math.degToRad(30);
	var startPush : h2d.col.Point;
	var moveCount = 0;

	public var isOrtho = false;
	public var isFps = false;
	public var isFlight = false;
	public var orthoZoom = 1.0;

	override function loadSettings(data : Dynamic) : Void {
		super.loadSettings(data);
		var cam = sceneEditor.scene.s3d.camera;
		cam.up.set(0,0,1,0);
		set(data.distance);
	}

	override public function saveSettings(data : Dynamic) : Void {
		data.distance = distance;
	}

	override function onEvent( e : hxd.Event ) {
		if(curPos == null) return;
		switch( e.kind ) {
		case EWheel:
			if (isOrtho) {
				if (e.wheelDelta > 0) {
					orthoZoom /= 1.1;
				}
				else {
					orthoZoom *= 1.1;
				}
			}
			else {
				if (pushing == 2 || pushing == 1) {
					if (e.wheelDelta > 0) {
						camSpeed /= 1.1;
					}
					else {
						camSpeed *= 1.1;
					}
				}
				else {
					zoom(e.wheelDelta);
				}
			}

		case EPush:
			pushing = e.button;
			if (pushing == 0 && K.isDown(K.ALT)) pushing = 2;
			pushTime = haxe.Timer.stamp();
			pushStartX = pushX = e.relX;
			pushStartY = pushY = e.relY;
			startPush = new h2d.col.Point(pushX, pushY);
			if( pushing == 2 ) {
				var se = sceneEditor;
				var selection = se.getSelection();
				var angle = hxd.Math.abs(Math.PI/2 - phi);
				if( selection.length == 0 && angle > groundSnapAngle ) {
					var visGround = se.screenToGround(se.scene.s2d.width / 2, se.scene.s2d.height / 2);
					var dist = se.screenDistToGround(se.scene.s2d.width / 2, se.scene.s2d.height / 2);
					if( dist != null ) {
						set(dist, null, null, visGround);
					}
				}
			}
			moveCount = 0;
			@:privateAccess scene.window.mouseMode = AbsoluteUnbound(true);
		case ERelease, EReleaseOutside:
			if( pushing == e.button || pushing == 2) {
				pushing = -1;
				startPush = null;
				if( e.kind == ERelease && haxe.Timer.stamp() - pushTime < 0.2 && hxd.Math.distance(e.relX - pushStartX,e.relY - pushStartY) < 5 )
					onClick(e);
				@:privateAccess scene.window.mouseMode = Absolute;
			}
		case EMove:
			// Windows bug that jumps movementX/Y on all browsers
			if( moveCount < 10 && Math.distanceSq(pushX - e.relX, pushY - e.relY) > 100000 ) {
				pushX = e.relX;
				pushY = e.relY;
				return;
			}
			moveCount++;

			if (isFps && !isOrtho) {
				switch( pushing ) {
					case 1:
						var m = 0.1 * panSpeed / 25;
						lookAround(-(e.relX - pushX) * m, (e.relY - pushY) * m);
						pushX = e.relX;
						pushY = e.relY;
					case 2:
						if(startPush != null && startPush.distance(new h2d.col.Point(e.relX, e.relY)) > 3) {
							var angle = hxd.Math.abs(Math.PI/2 - phi);
							if(K.isDown(K.SHIFT) || angle < groundSnapAngle) {
								var m = 0.001 * curPos.x * panSpeed / 25;
								pan(-(e.relX - pushX) * m, (e.relY - pushY) * m);
							}
							else {
								var se = sceneEditor;
								var fromPt = se.screenToGround(startPush.x, startPush.y);
								var toPt = se.screenToGround(startPush.x+e.relX-pushX, startPush.y+e.relY-pushY);
								if(fromPt == null || toPt == null)
									return;
								var delta = toPt.sub(fromPt).toVector();
								delta.w = 0;
								targetOffset = targetOffset.sub(delta);
							}
						}
						pushX = e.relX;
						pushY = e.relY;
					default:
				}
			}
			else {
				switch( pushing ) {
					case 1:
						if(startPush != null && startPush.distance(new h2d.col.Point(e.relX, e.relY)) > 3) {
							var angle = hxd.Math.abs(Math.PI/2 - phi);
							if(K.isDown(K.SHIFT) || angle < groundSnapAngle) {
								var m = 0.001 * curPos.x * panSpeed / 25;
								pan(-(e.relX - pushX) * m, (e.relY - pushY) * m);
							}
							else {
								var se = sceneEditor;
								var fromPt = se.screenToGround(startPush.x, startPush.y);
								var toPt = se.screenToGround(startPush.x+e.relX-pushX, startPush.y+e.relY-pushY);
								if(fromPt == null || toPt == null)
									return;
								var delta = toPt.sub(fromPt).toVector();
								delta.w = 0;
								targetOffset = targetOffset.sub(delta);
							}
						}
						pushX = e.relX;
						pushY = e.relY;
					case 2:
						rot(e.relX - pushX, e.relY - pushY);
						pushX = e.relX;
						pushY = e.relY;
					default:
				}
			}

		case EFocus:
			@:privateAccess scene.window.mouseMode = Absolute;
		default:
		}
	}

	function lookAround(dtheta : Float, dphi : Float) {
		var cam = getScene().camera;

		var tx = targetOffset.x + distance * Math.cos(theta) * Math.sin(phi) ;
		var ty = targetOffset.y + distance * Math.sin(theta) * Math.sin(phi);
		var tz = targetOffset.z + distance * Math.cos(phi);

		targetPos.y = theta - dtheta;
		targetPos.z = phi - dphi;
		if (isOrtho) {
			curOffset.x = 10000.0;
		}
		else {
			curOffset.x = curOffset.w;
		}
		targetOffset.x = tx - distance * Math.cos(targetPos.y) * Math.sin(targetPos.z);
		targetOffset.y = ty - distance * Math.sin(targetPos.y) * Math.sin(targetPos.z);
		targetOffset.z = tz - distance * Math.cos(targetPos.z);
		curOffset.load(targetOffset);
		curPos.load(targetPos);
	}

	function moveKeys() {
		var mov = new h3d.Vector();
		if( K.isDown(K.UP) || K.isDown(K.Z) || K.isDown(K.W) )
			mov.x += 1;
		if( K.isDown(K.DOWN) || K.isDown(K.S) )
			mov.x -= 1;
		if( K.isDown(K.LEFT) || K.isDown(K.Q) || K.isDown(K.A) )
			mov.y -= 1;
		if( K.isDown(K.RIGHT) || K.isDown(K.D) )
			mov.y += 1;

		if (isFps) {
			mov.set(-mov.y, 0, -mov.x);
			if( mov.x == 0 && mov.z == 0 )
				return;
			mov.transform3x3(scene.camera.getInverseView());
			var moveSpeed = Ide.inst.currentConfig.get("sceneeditor.camera.moveSpeed", 1.5) * camSpeed;

			var delta = mov.multiply(0.1 * moveSpeed);
			delta.w = 0;
			targetOffset = targetOffset.sub(delta);
		}
		else {
			if( mov.x == 0 && mov.y == 0 )
				return;
			var dir = new h3d.Vector(
				mov.x * Math.cos(theta) + mov.y * Math.cos(Math.PI / 2 + theta),
				mov.x * Math.sin(theta) + mov.y * Math.sin(Math.PI / 2 + theta)
			);
			var moveSpeed = Ide.inst.currentConfig.get("sceneeditor.camera.moveSpeed", 1.5);
	
			var delta = dir.multiply(0.01 * moveSpeed * (distance + scene.camera.zNear));
			delta.w = 0;
			targetOffset = targetOffset.sub(delta);
		}
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		if( pushing == 2 || pushing == 1) {
			moveKeys();
		}

		/*if ( K.isPressed(K.F7)) {
			isOrtho = !isOrtho;
		}

		if ( K.isPressed(K.F6)) {
			isFps = !isFps;
		}*/

		var cam = getScene().camera;


		if (isOrtho) {
			if (cam.orthoBounds == null) {
				cam.orthoBounds = new h3d.col.Bounds();
			}

			cam.orthoBounds.xMax = 20.0 * orthoZoom;
			cam.orthoBounds.yMax = cam.orthoBounds.xMax / cam.screenRatio;
			cam.orthoBounds.xMin = -20.0 * orthoZoom;
			cam.orthoBounds.yMin = cam.orthoBounds.xMin / cam.screenRatio;
			cam.orthoBounds.zMin = 20;
			cam.orthoBounds.zMax = -20;
		}
		else {
			cam.orthoBounds = null;
			curOffset.w = wantedFOV;
			targetOffset.w = wantedFOV;
		}

		var old = ctx.elapsedTime;
		ctx.elapsedTime = hxd.Timer.dt;
		super.sync(ctx);
		ctx.elapsedTime = old;
	}
}

class FlightController extends CameraControllerBase {
	var startPush : h2d.col.Point;

	
	var camPos : h3d.Vector = new h3d.Vector();
	var camRot : h3d.Quat = new h3d.Quat();
	var mat : h3d.Matrix = new h3d.Matrix();

	public function new(parent, sceneEditor) {
		super(parent, sceneEditor);
		camRot.identity();
	}
	
	
	function moveKeys() {
		var mov = new h3d.Vector();
		var roll = 0.0;
		if( K.isDown(K.UP) || K.isDown(K.Z) || K.isDown(K.W) )
			mov.x += 1;
		if( K.isDown(K.DOWN) || K.isDown(K.S) )
			mov.x -= 1;
		if( K.isDown(K.LEFT) || K.isDown(K.Q) )
			mov.y -= 1;
		if( K.isDown(K.RIGHT) || K.isDown(K.D) )
			mov.y += 1;
		if (K.isDown(K.A))
			if (!K.isDown(K.SHIFT))
				roll += 1;
			else
				mov.z += 1;
		if (K.isDown(K.E))
			if (!K.isDown(K.SHIFT))
				roll -= 1;
			else
				mov.z -= 1;

		mov.scale(Ide.inst.currentConfig.get("sceneeditor.camera.moveSpeed", 1.5) * camSpeed);
		tmpVec.load(mat.front());
		tmpVec.scale(mov.x);
		camPos = camPos.add(tmpVec);

		tmpVec.load(mat.right());
		tmpVec.scale(mov.y);
		camPos = camPos.add(tmpVec);

		tmpVec.load(mat.up());
		tmpVec.scale(mov.z);
		camPos = camPos.add(tmpVec);

		camPos.w = 1.0;

		if (roll != 0) {
			lookAround(0,0,roll * 0.05);
		}
	}

	override function loadFromCamera( animate = false ) {
		//super.loadFromCamera(animate);
		var cam = sceneEditor.scene.s3d.camera;
		var fwd = cam.target.sub(cam.pos); fwd.normalize();
		var up = new h3d.Vector(0,0,1);
		var left = fwd.cross(up); left.normalize();
		up = left.cross(fwd); up.normalize();
		mat.identity();
		mat._11 = fwd.x;
		mat._12 = fwd.y;
		mat._13 = fwd.z;
		mat._21 = -left.x;
		mat._22 = -left.y;
		mat._23 = -left.z;
		mat._31 = up.x;
		mat._32 = up.y;
		mat._33 = up.z;
		camRot.initRotateMatrix(mat);
		camRot.normalize();
		camPos.load(cam.pos);
		syncCamera();
	}

	override function onEvent( e : hxd.Event ) {
		if(curPos == null) return;
		switch( e.kind ) {
		case EWheel:
			if (pushing == 2 || pushing == 1) {
				if (e.wheelDelta > 0) {
					camSpeed /= 1.1;
				}
				else {
					camSpeed *= 1.1;
				}
			}
		case EPush:
			pushing = e.button;
			if (pushing == 0 && K.isDown(K.ALT)) pushing = 2;
			pushTime = haxe.Timer.stamp();
			pushStartX = pushX = e.relX;
			pushStartY = pushY = e.relY;
			startPush = new h2d.col.Point(pushX, pushY);
			if( pushing == 2 ) {
				/*var se = sceneEditor;
				var selection = se.getSelection();
				var angle = hxd.Math.abs(Math.PI/2 - phi);
				if( selection.length == 0 && angle > groundSnapAngle ) {
					var visGround = se.screenToGround(se.scene.s2d.width / 2, se.scene.s2d.height / 2);
					var dist = se.screenDistToGround(se.scene.s2d.width / 2, se.scene.s2d.height / 2);
					if( dist != null ) {
						set(dist, null, null, visGround);
					}
				}*/
			}
			/*moveCount = 0;*/
			@:privateAccess scene.window.mouseMode = AbsoluteUnbound(true);
		case ERelease, EReleaseOutside:
			if( pushing == e.button || pushing == 2) {
				pushing = -1;
				startPush = null;
				if( e.kind == ERelease && haxe.Timer.stamp() - pushTime < 0.2 && hxd.Math.distance(e.relX - pushStartX,e.relY - pushStartY) < 5 )
					onClick(e);
				@:privateAccess scene.window.mouseMode = Absolute;
			}
		case EMove:
			// Windows bug that jumps movementX/Y on all browsers
			/*if( moveCount < 10 && Math.distanceSq(pushX - e.relX, pushY - e.relY) > 100000 ) {
				pushX = e.relX;
				pushY = e.relY;
				return;
			}
			moveCount++;*/
			switch( pushing ) {
				case 1:
					var m = 0.1 * panSpeed / 25;
					lookAround((e.relX - pushX) * m, (e.relY - pushY) * m, 0.0);
					pushX = e.relX;
					pushY = e.relY;
				case 2:
					if(startPush != null && startPush.distance(new h2d.col.Point(e.relX, e.relY)) > 3) {
						var angle = hxd.Math.abs(Math.PI/2 - phi);

						var se = sceneEditor;
						var fromPt = se.screenToGround(startPush.x, startPush.y);
						var toPt = se.screenToGround(startPush.x+e.relX-pushX, startPush.y+e.relY-pushY);
						if(fromPt == null || toPt == null)
							return;
						var delta = toPt.sub(fromPt).toVector();
						delta.w = 0;
						targetOffset = targetOffset.sub(delta);
					}
					pushX = e.relX;
					pushY = e.relY;
				default:
			}

		case EFocus:
			@:privateAccess scene.window.mouseMode = Absolute;
		default:
		}
	}

	static var tmpVec = new h3d.Vector();
	static var tmpQuat = new h3d.Quat();
	function lookAround(dtheta : Float, dphi : Float, djesaispas : Float) {
		if (dtheta != 0) {
			tmpVec.set(0.0,0.0,1.0);
			tmpQuat.initRotateAxis(tmpVec.x, tmpVec.y, tmpVec.z, dtheta);
			camRot.multiply(camRot, tmpQuat);
		}


		if (dphi != 0) {
			tmpVec.set(0.0,1.0,0.0);

			//tmpVec.load(mat.right());
			tmpQuat.initRotateAxis(tmpVec.x, tmpVec.y, tmpVec.z, dphi);
			camRot.multiply(camRot, tmpQuat);
		}

		if (djesaispas != 0) {
			tmpVec.set(1.0,0.0,0.0);
			tmpQuat.initRotateAxis(tmpVec.x, tmpVec.y, tmpVec.z, djesaispas);
			camRot.multiply(camRot, tmpQuat);
		}


		camRot.normalize();
	}

	
	override function syncCamera() {
		var cam = getScene().camera;
		mat = camRot.toMatrix();
		cam.target.load(camPos);
		cam.target = cam.target.add(mat.front());
		cam.pos.load(camPos);
		cam.up.load(mat.up());
		cam.fovY = wantedFOV;
		cam.zNear = 0.01;
		cam.zFar = 10000.0;
		cam.update();
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		moveKeys();
		//lookAround(0.01, 0.0);
		syncCamera();
		trace(camPos);
		trace(camRot);
	}
}