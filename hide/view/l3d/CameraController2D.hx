package hide.view.l3d;

class CameraController2D extends h2d.Object {

	public var friction = 0.4;
	public var zoomAmount = 1.15;
	public var panSpeed = 1.;
	public var smooth = 0.6;

	var scene : h2d.Scene;
	var pushing = -1;
	var pushX = 0.;
	var pushY = 0.;
	var pushStartX = 0.;
	var pushStartY = 0.;
	var moveX = 0.;
	var moveY = 0.;
	var pushTime : Float;
	var curPos = new h3d.col.Point(0,0,1);
	var targetPos = new h3d.col.Point(0,0,1);

	public function new(?parent) {
		super(parent);
		name = "CameraController";
	}

	/**
		Set the controller parameters.
		Distance is ray distance from target.
		Theta and Phi are the two spherical angles
		Target is the target position
	**/
	public function set( x : Float, y : Float, ?zoom : Float ) {
		targetPos.x = x;
		targetPos.y = y;
		if( zoom != null ) targetPos.z = zoom;
	}

	/**
		Load current position from current camera position and target.
		Call if you want to modify manually the camera.
	**/
	public function loadFromScene( animate = false ) {
		var scene = if( scene == null ) getScene() else scene;
		if( scene == null ) throw "Not in scene";
		targetPos.set( (scene.width*0.5-parent.x) / parent.scaleX, (scene.height*0.5-parent.y) / parent.scaleX, parent.scaleX);
		if( !animate )
			toTarget();
		else
			syncCamera(); // reset camera to current
	}

	/**
		Initialize to look at the whole scene, based on reported scene bounds.
	**/
	public function initFromScene() {
		var scene = getScene();
		if( scene == null ) throw "Not in scene";
		var bounds = parent.getBounds(parent);
		var center = bounds.getCenter();

		var scale = Math.min(1, Math.min(scene.width / bounds.width, scene.height / bounds.height));
		parent.setScale(scale);
		parent.x = scene.width * 0.5 - center.x;
		parent.y = scene.height * 0.5 - center.y;
		loadFromScene();
	}

	/**
		Stop animation by directly moving to end position.
		Call after set() if you don't want to animate the change
	**/
	public function toTarget() {
		curPos.load(targetPos);
		syncCamera();
	}

	override function onAdd() {
		super.onAdd();
		scene = getScene();
		scene.addEventListener(onEvent);
		targetPos.load(curPos);
	}

	override function onRemove() {
		super.onRemove();
		scene.removeEventListener(onEvent);
		scene = null;
	}

	public dynamic function onClick( e : hxd.Event ) {
	}

	function onEvent( e : hxd.Event ) {

		var p : h2d.Object = this;
		while( p != null ) {
			if( !p.visible ) {
				e.propagate = true;
				return;
			}
			p = p.parent;
		}

		switch( e.kind ) {
		case EWheel:
			zoom(e.wheelDelta);
		case EPush:
			@:privateAccess scene.events.startDrag(onEvent, function() pushing = -1, e);
			pushing = e.button;
			pushTime = haxe.Timer.stamp();
			pushStartX = pushX = e.relX;
			pushStartY = pushY = e.relY;
		case ERelease, EReleaseOutside:
			if( pushing == e.button ) {
				pushing = -1;
				@:privateAccess scene.events.stopDrag();
				if( e.kind == ERelease && haxe.Timer.stamp() - pushTime < 0.2 && hxd.Math.distance(e.relX - pushStartX,e.relY - pushStartY) < 5 )
					onClick(e);
			}
		case EMove:
			switch( pushing ) {
			case 1:
				pan((e.relX - pushX) * panSpeed, (e.relY - pushY) * panSpeed);
				pushX = e.relX;
				pushY = e.relY;
			default:
			}
		default:
		}
	}

	function zoom(delta:Float) {
		targetPos.z *= Math.pow(zoomAmount, -delta);
	}

	function rot(dx, dy) {
		moveX += dx;
		moveY += dy;
	}

	function pan(dx:Float, dy:Float) {
		targetPos.x -= dx / parent.scaleX;
		targetPos.y -= dy / parent.scaleY;
	}

	function syncCamera() {
		var scene = getScene();
		//if( scene == null ) return;
		parent.setScale(curPos.z);
		parent.x = scene.width * 0.5 - curPos.x * parent.scaleX;
		parent.y = scene.height * 0.5 - curPos.y * parent.scaleY;
	}

	override function sync(ctx:h2d.RenderContext) {

		var p : h2d.Object = this;
		while( p != null ) {
			if( !p.visible ) {
				super.sync(ctx);
				return;
			}
			p = p.parent;
		}

		/*
		if( moveX != 0 ) {
			targetPos.y += moveX * 0.003 * rotateSpeed;
			moveX *= 1 - friction;
			if( Math.abs(moveX) < 1 ) moveX = 0;
		}

		if( moveY != 0 ) {
			targetPos.z -= moveY * 0.003 * rotateSpeed;
			var E = 2e-5;
			var bound = Math.PI - E;
			if( targetPos.z < E ) targetPos.z = E;
			if( targetPos.z > bound ) targetPos.z = bound;
			moveY *= 1 - friction;
			if( Math.abs(moveY) < 1 ) moveY = 0;
		}*/

		var dt = hxd.Math.min(1, 1 - Math.pow(smooth, ctx.elapsedTime * 60));
		curPos.lerp(curPos, targetPos, dt );
		syncCamera();

		super.sync(ctx);
	}

}
