package hide.view;

import hxd.Math;
import hxd.Key as K;

class CamController extends h3d.scene.CameraController {
	public var groundSnapAngle = hxd.Math.degToRad(30);
	var sceneEditor : hide.comp.SceneEditor;
	var startPush : h2d.col.Point;
	var moveCount = 0;

	public var isOrtho = false;
	public var isFps = false;
	public var orthoZoom = 1.0;
	public var wantedFOV = 90.0;
	public var camSpeed = 1.0;


	public function new(parent, sceneEditor) {
		super(null, parent);
		this.sceneEditor = sceneEditor;
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