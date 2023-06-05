package hrt.prefab.l3d;

// NOTE(ces) : Not Tested

class GameController extends Object3D {

	@:s public var moveSpeed : Float = 1.;
	@:s public var zOffset : Float = 0.0;
	@:s public var followGround : Bool = true;
	@:s public var cameraFollowGround : Bool = true;
	@:s public var startFullScreen : Bool = true;
	@:s public var animIdle : String = "idle";
	@:s public var animMove : String = "walk";
	@:s public var animJump : String = "jump";
	@:s public var animFall : String = "fall";
	@:s public var animSmooth : Float = 0.2;
	@:s public var jumpPower : Float = 0.;
	@:s public var jumpPowerHold : Float = 0.;
	@:s public var jumpPowerHoldTime : Float = 0.;
	@:s public var gravity : Float = 50.;

	#if editor

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		parent3d.ignoreParentTransform = true;
		return parent3d;
	}


	override function edit(ctx:hide.prefab.EditContext) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('
			<div class="group" name="Control">
				<dl>
					<dt>Move Speed</dt><dd><input type="range" min="0" max="10" field="moveSpeed"/></dd>
					<dt>Z Offset</dt><dd><input type="range" min="0" max="10" field="zOffset"/></dd>
					<dt>Follow Ground</dt><dd><input type="checkbox" field="followGround"/></dd>
					<dt>Camera Follow Ground</dt><dd><input type="checkbox" field="cameraFollowGround"/></dd>
					<dt>Start Full Screen</dt><dd><input type="checkbox" field="startFullScreen"/></dd>
				</dl>
			</div>
			<div class="group" name="Jump">
				<dl>
					<dt>Power</dt><dd><input type="range" min="0" max="100" field="jumpPower"/></dd>
					<dt>Gravity</dt><dd><input type="range" min="0" max="100" field="gravity"/></dd>
					<dt>Power Hold</dt><dd><input type="range" min="0" max="10" field="jumpPowerHold"/></dd>
					<dt>Power Hold Time</dt><dd><input type="range" min="0" max="1" field="jumpPowerHoldTime"/></dd>
				</dl>
			</div>
			<div class="group" name="Animations">
				<dl>
					<dt>Idle</dt><dd><input field="animIdle"/></dd>
					<dt>Move</dt><dd><input field="animMove"/></dd>
					<dt>Jump</dt><dd><input field="animJump"/></dd>
					<dt>Fall</dt><dd><input field="animFall"/></dd>
					<dt>Smooth</dt><dd><input type="range" min="0" max="1" field="animSmooth"/></dd>
				</dl>
			</div>
		'),this);

		var active = false;
		var obj = local3d;
		var camSave = null;
		var dummy : h3d.scene.Object = null;
		var cam = local3d.getScene().camera;
		var camRot : h3d.Vector = null;
		var startCamRot : h3d.Vector = null;
		var zSpeed = 0.;
		var startJumpTime = 1e9;

		function selectRec( p : Prefab, b : Bool ) {
			if( !p.setSelected(b) )
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

		var currentAnim = new Map<h3d.scene.Object,String>();
		var baseZ = obj.z;

		function playAnim( anim : String ) {
			for( o in getAll(Model,true) ) {
				if( o.source == null ) continue;

				if( currentAnim.get(local3d) == anim )
					continue;

				var animList = try ctx.scene.listAnims(o.source) catch(e: Dynamic) [];
				for( a2 in animList ) {
					if( ctx.scene.animationName(a2).toLowerCase() == anim.toLowerCase() ) {
						local3d.playAnimation(shared.loadAnimation(a2));
						if( animSmooth > 0 )
							local3d.switchToAnimation(new h3d.anim.SmoothTarget(local3d.currentAnimation,animSmooth));
						currentAnim.set(local3d, anim);
						break;
					}
				}
			}
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

					obj.setTransform(getTransform());
					var camView = @:privateAccess ctx.scene.editor.sceneData.getOpt(Camera);
					if( camView != null )
						camView.applyTo(cam);
					var delta = cam.pos.sub(cam.target);
					var q = new h3d.Quat();
					q.initDirection(delta);
					startCamRot = q.toEuler();
					startCamRot.w = delta.length();
					camRot = startCamRot.clone();

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

			inline function rotateVector(v : h3d.Vector, x, y, z) {
				var m = new h3d.Matrix();
				m.initRotation(x, y, z);
				v.transform(m);
			}

			if( pad.isDown(pad.config.Y) ) dt *= 10;
			if( pad.isDown(pad.config.X) ) {
				camRot = startCamRot.clone();
			}

			if( pad.isDown(pad.config.A) ) {
				if( zSpeed == 0 ) {
					zSpeed = -jumpPower;
					startJumpTime = haxe.Timer.stamp();
				} else if( zSpeed < 0 && haxe.Timer.stamp() - startJumpTime < jumpPowerHoldTime )
					zSpeed -= (jumpPowerHold / jumpPowerHoldTime) * dt;
			}

			obj.z -= zSpeed * dt;
			zSpeed += gravity * dt;

			// Rotate cam
			if(hxd.Math.abs(pad.rxAxis) > 0.2 || hxd.Math.abs(pad.ryAxis) > 0.2) {
				camRot.z += pad.rxAxis * dt * 2.0;
				camRot.y -= pad.ryAxis * dt * 1.0;
			}

			// Zoom
			var z = pad.values[pad.config.LT] - pad.values[pad.config.RT];
			if(z != 0.0)
				camRot.w *= Math.exp(1.0 * z * dt);

			var camDelta = new h3d.Vector(camRot.w);
			rotateVector(camDelta, 0, camRot.y, camRot.z);

			var gz = ctx.scene.editor.getZ(obj.x, obj.y);
			var groundZ = followGround ? gz : baseZ;

			// Move
			var moving = hxd.Math.abs(pad.xAxis) > 0.2 || hxd.Math.abs(pad.yAxis) > 0.2;
			if( force || moving ) {
				var delta = new h3d.Vector(pad.yAxis,-pad.xAxis,0);
				rotateVector(delta, 0, 0, camRot.z);
				delta.scale(dt * moveSpeed);
				obj.x += delta.x;
				obj.y += delta.y;
				obj.setRotation(0, 0, Math.atan2(delta.y, delta.x));
			}

			if( obj.z < groundZ ) {
				zSpeed = 0;
				obj.z = groundZ;
			}
			cam.target.set(obj.x, obj.y, (cameraFollowGround ? obj.z : 0) + zOffset);

			if( zSpeed < 0 )
				playAnim(animJump);
			else if( zSpeed > 0 )
				playAnim(animFall)
			else if( moving )
				playAnim(animMove);
			else
				playAnim(animIdle);

			cam.pos = cam.target.add(camDelta);
			if( followGround )
				cam.pos.z = hxd.Math.max(cam.pos.z, gz);
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

	static var _ = Prefab.register("gamectrl", GameController);

}