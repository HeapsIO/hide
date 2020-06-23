package hrt.prefab.l3d;

class GameController extends Object3D {

	public var moveSpeed : Float = 1.;
	public var followGround : Bool = true;
	public var cameraFollowGround : Bool = true;

	override function load(obj:Dynamic) {
		super.load(obj);
		moveSpeed = obj.moveSpeed;
		followGround = obj.followGround;
		cameraFollowGround = obj.cameraFollowGround;
	}

	override function save():{} {
		var obj : Dynamic = super.save();
		obj.moveSpeed = moveSpeed;
		obj.followGround = followGround;
		obj.cameraFollowGround = cameraFollowGround;
		return obj;
	}

	#if editor

	override function makeInstance(ctx:Context):Context {
		ctx = super.makeInstance(ctx);
		ctx.local3d.ignoreParentTransform = true;
		return ctx;
	}

	override function edit(ctx:EditContext) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('
			<div class="group" name="Control">
				<dl>
					<dt>Move Speed</dt><dd><input type="range" min="0" max="10" field="moveSpeed"/></dd>
					<dt>Follow Ground</dt><dd><input type="checkbox" field="followGround"/></dd>
					<dt>Camera Follow Ground</dt><dd><input type="checkbox" field="cameraFollowGround"/></dd>
				</dl>
			</div>
		'),this);

		var active = false;
		var obj = ctx.getContext(this).local3d;
		var camSave = null;
		var dummy : h3d.scene.Object = null;
		var cam = ctx.scene.s3d.camera;

		function restore() {
			// restore position
			obj.setTransform(getTransform());
			// restore camera
			cam.pos.load(camSave.pos);
			cam.target.load(camSave.target);
			ctx.scene.editor.cameraController.loadFromCamera();
			@:privateAccess ctx.scene.editor.showGizmo = true;
			if( dummy != null ) dummy.remove();
		}

		function onUpdate( dt : Float ) {
			var pad = ctx.ide.gamePad;
			var force = false;
			if( pad.isPressed(pad.config.start) ) {
				active = !active;
				if( !active ) {
					restore();
				} else {
					@:privateAccess ctx.scene.editor.showGizmo = false;
					camSave = { pos : cam.pos.clone(), target : cam.target.clone() };
					if( obj.numChildren == 0 )
						dummy = new h3d.scene.Box(obj);
					force = true;
				}
			}
			if( !active )
				return;

			if( !force && pad.xAxis == 0 && pad.yAxis == 0 )
				return;


			var delta = cam.pos.sub(cam.target);
			var ax = cam.getViewDirection(1,0,0);
			ax.z = 0;
			ax.normalize();
			obj.x += (pad.xAxis * ax.x - pad.yAxis * ax.y) * dt * moveSpeed;
			obj.y += (pad.xAxis * ax.y + pad.yAxis * ax.x) * dt * moveSpeed;

			var gz = ctx.scene.editor.getZ(obj.x, obj.y);
			if( followGround )
				obj.z = gz;
			cam.target.set(obj.x, obj.y, cameraFollowGround ? gz : 0);
			cam.pos = cam.target.add(delta);
			cam.update();
			ctx.scene.editor.cameraController.loadFromCamera();
		}

		ctx.scene.addListener(onUpdate);
		ctx.cleanups.push(() -> {
			if( active ) restore();
			ctx.scene.removeListener(onUpdate);
		});
	}
	#end

	static var _ = Library.register("gamectrl", GameController);

}