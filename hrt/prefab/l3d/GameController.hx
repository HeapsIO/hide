package hrt.prefab.l3d;

class GameController extends Object3D {

	@:s public var moveSpeed : Float = 1.;
	@:s public var followGround : Bool = true;
	@:s public var cameraFollowGround : Bool = true;
	@:s public var startFullScreen : Bool = true;

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
					<dt>Start Full Screen</dt><dd><input type="checkbox" field="startFullScreen"/></dd>
				</dl>
			</div>
		'),this);

		var active = false;
		var lctx = ctx.getContext(this);
		var obj = lctx.local3d;
		var camSave = null;
		var dummy : h3d.scene.Object = null;
		var cam = ctx.scene.s3d.camera;

		function selectRec( p : Prefab, b : Bool ) {
			if( !p.setSelected(ctx.getContext(p), b) )
				return;
			for( c in p.children )
				selectRec(c, b);
		}

		function restore() {
			// restore position
			obj.setTransform(getTransform());
			// restore camera
			cam.pos.load(camSave.pos);
			cam.target.load(camSave.target);
			cam.zFar = camSave.zFar;
			cam.fovY = camSave.fovY;
			ctx.scene.editor.cameraController.loadFromCamera();
			@:privateAccess ctx.scene.editor.showGizmo = true;
			if( dummy != null ) dummy.remove();
			if( startFullScreen ) ctx.scene.editor.setFullScreen(false);
			selectRec(this, true);
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
					camSave = { pos : cam.pos.clone(), target : cam.target.clone(), fovY : cam.fovY, zFar : cam.zFar };
					var camView = @:privateAccess ctx.scene.editor.sceneData.get(Camera);
					if( camView != null )
						camView.applyTo(cam);
					if( obj.numChildren == 0 )
						dummy = new h3d.scene.Box(obj);
					if( startFullScreen )
						ctx.scene.editor.setFullScreen(true);
					force = true;
					selectRec(this, false);
				}
			}
			if( !active )
				return;

			if( !force && pad.xAxis == 0 && pad.yAxis == 0 )
				return;

			if( pad.isDown(pad.config.A) ) dt *= 10;


			var delta = cam.pos.sub(cam.target);
			var ax = cam.getViewDirection(1,0,0);
			ax.z = 0;
			ax.normalize();
			obj.x += (pad.xAxis * ax.x - pad.yAxis * ax.y) * dt * moveSpeed;
			obj.y += (pad.xAxis * ax.y + pad.yAxis * ax.x) * dt * moveSpeed;
			obj.setRotation(0, 0, Math.atan2(pad.yAxis, pad.xAxis));

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