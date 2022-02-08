package hide.view;

import hxd.Math;
import hxd.Key as K;

class CamController extends h3d.scene.CameraController {
	public var groundSnapAngle = hxd.Math.degToRad(30);
	var sceneEditor : hide.comp.SceneEditor;
	var startPush : h2d.col.Point;
	var moveCount = 0;

	public function new(parent, sceneEditor) {
		super(null, parent);
		this.sceneEditor = sceneEditor;
	}

	override function onEvent( e : hxd.Event ) {
		if(curPos == null) return;
		switch( e.kind ) {
		case EWheel:
			zoom(e.wheelDelta);
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
			@:privateAccess scene.window.mouseLock = true;
		case ERelease, EReleaseOutside:
			if( pushing == e.button || pushing == 2) {
				pushing = -1;
				startPush = null;
				if( e.kind == ERelease && haxe.Timer.stamp() - pushTime < 0.2 && hxd.Math.distance(e.relX - pushStartX,e.relY - pushStartY) < 5 )
					onClick(e);
				@:privateAccess scene.window.mouseLock = false;
			}
		case EMove:
			// Windows bug that jumps movementX/Y on all browsers
			if( moveCount < 10 && Math.distanceSq(pushX - e.relX, pushY - e.relY) > 100000 ) {
				pushX = e.relX;
				pushY = e.relY;
				return;
			}
			moveCount++;

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
						var fromPt = se.screenToGround(pushX, pushY);
						var toPt = se.screenToGround(e.relX, e.relY);
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
		case EFocus:
			@:privateAccess scene.window.mouseLock = false;
		default:
		}
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

	override function sync(ctx : h3d.scene.RenderContext) {
		if( pushing == 2 ) {
			moveKeys();
		}

		var old = ctx.elapsedTime;
		ctx.elapsedTime = hxd.Timer.dt;
		super.sync(ctx);
		ctx.elapsedTime = old;
	}
}