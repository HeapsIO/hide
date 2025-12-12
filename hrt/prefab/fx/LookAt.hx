package hrt.prefab.fx;

@:access(hrt.prefab.fx.LookAt)
class LookAtObject extends h3d.scene.Object {
	var target: h3d.scene.Object;
	var definition: LookAt;

	public function new(parent, def) {
		super(parent);
		this.definition = def;
	}

	static var tmpMat = new h3d.Matrix();
	static var deltaVec = new h3d.Vector();
	static var lookAtUp = new h3d.Vector();
	static var tempQ = new h3d.Quat();

	override function syncRec( ctx ) {
		posChanged = true;
		super.syncRec(ctx);
	}

	var guard: Int = 0;
	override function syncPos() {
		if (guard != 0)
			return;
		guard++;

		if( parent != null ) parent.syncPos();
		if( posChanged ) {
			posChanged = false;
			calcAbsPos();
			for( c in children )
				c.posChanged = true;
		}

		guard--;
	}

	override function calcAbsPos() {
		super.calcAbsPos();
		var scene = getScene();
		var pos = new h3d.Vector();
		pos.load(absPos.getPosition());
		var lookAtPos = new h3d.Vector();
		if(target != null) {
			var abs = target.getAbsPos();
			lookAtPos.load(abs.getPosition());
			lookAtUp.load(abs.up());
		} else {
			if(scene == null || scene.camera == null) {
				super.calcAbsPos();
				return;
			}
			var cam = scene.camera;
			if ( definition.faceTargetForward )
				lookAtPos.load(pos - (cam.target - cam.pos));
			else
				lookAtPos.load(cam.pos);
			lookAtUp.load(cam.up);
		}

		deltaVec.load(lookAtPos - pos);
		if(deltaVec.lengthSq() < 0.001)
			return;

		var lockAxis = new h3d.Vector();
		if(definition.lockAxis != null)
			lockAxis.set(definition.lockAxis[0], definition.lockAxis[1], definition.lockAxis[2]);

		if(lockAxis.lengthSq() > 0.001) {
			tmpMat.load(parent.getAbsPos());
			tmpMat.invert();
			lookAtPos.transform(tmpMat);
			deltaVec.set(lookAtPos.x - x, lookAtPos.y - y, lookAtPos.z - z);

			var invParentQ = tempQ;
			invParentQ.initRotateMatrix(tmpMat);

			var targetOnPlane = h3d.col.Plane.fromNormalPoint(lockAxis.toPoint(), new h3d.col.Point()).project(deltaVec.toPoint()).toVector();
			targetOnPlane.normalize();
			var referenceAxis = inline new h3d.Vector(targetOnPlane.x != 0 ? 1 : 0, targetOnPlane.x != 0 ? 0 : 1, 0);
			var angle = hxd.Math.acos(referenceAxis.dot(targetOnPlane));

			var cross = referenceAxis.cross(deltaVec);
			if(lockAxis.dot(cross) < 0)
				angle = -angle;

			var q = getRotationQuat();
			q.initRotateAxis(lockAxis.x, lockAxis.y, lockAxis.z, angle);
			q.normalize();
			setRotationQuat(q);

			super.calcAbsPos();
			pos.load(absPos.getPosition());
			if (definition.constantScreenSize) {
				var v = pos - scene.camera.pos;
				var scaleFactor = v.length();
				absPos._11 *= scaleFactor;
				absPos._12 *= scaleFactor;
				absPos._13 *= scaleFactor;
				absPos._21 *= scaleFactor;
				absPos._22 *= scaleFactor;
				absPos._23 *= scaleFactor;
				absPos._31 *= scaleFactor;
				absPos._32 *= scaleFactor;
				absPos._33 *= scaleFactor;
			}
		} else {
			tmpMat.load(absPos);
			var scale = tmpMat.getScale();

			if (definition.constantScreenSize) {
				var v = pos - scene.camera.pos;
				scale *= v.length();
			}

			qRot.initDirection(deltaVec, lookAtUp);
			qRot.toMatrix(absPos);
			absPos._11 *= scale.x;
			absPos._12 *= scale.x;
			absPos._13 *= scale.x;
			absPos._21 *= scale.y;
			absPos._22 *= scale.y;
			absPos._23 *= scale.y;
			absPos._31 *= scale.z;
			absPos._32 *= scale.z;
			absPos._33 *= scale.z;
			absPos._41 = tmpMat.tx;
			absPos._42 = tmpMat.ty;
			absPos._43 = tmpMat.tz;
		}
	}
}

@:allow(hrt.prefab.fx.LookAt.LookAtInstance)
class LookAt extends Object3D {

	@:s var target(default,null) : String;
	@:s var faceTargetForward : Bool;
	@:s var constantScreenSize : Bool;
	@:s var lockAxis: Array<Float> = [0,0,0];

	override function updateInstance(?propName:String) {
		super.updateInstance(propName);
		var targetObj = null;
		if(target != "camera")
			targetObj = locateObject(target);
		var lookAt = Std.downcast(local3d, LookAtObject);
		if (lookAt != null)
			@:privateAccess lookAt.target = targetObj;
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		var obj = new LookAtObject(parent3d, this);
		obj.name = this.name;
		return obj;
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "cog",
			name : "LookAt"
		};
	}

	override function edit(ctx:hide.prefab.EditContext) {
		super.edit(ctx);
		var group = new hide.Element('
		<div class="group" name="LookAt">
			<dl>
				<dt>Target</dt><dd><select field="target"><option value="">-- Choose --</option></select></dd>
				<dt>Face target forward</dt><dd><input type="checkbox" field="faceTargetForward"/></dd>
				<dt>Constant screen size</dt><dd><input type="checkbox" field="constantScreenSize"/></dd>
			</dl>
		</div>');

		group.append(hide.comp.PropsEditor.makePropsList([
			{ name: "lockAxis", t: PVec(3), def: [1,0,0] }
		]));

		var props = ctx.properties.add(group ,this);

		var select = props.find("select");
		var opt = new hide.Element("<option>").attr("value", "camera").html("Camera");
		select.append(opt);

		for( path in ctx.getNamedObjects() ) {
			var parts = path.split(".");
			var opt = new hide.Element("<option>").attr("value", path).html([for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop());
			select.append(opt);
		}

		select.val(Reflect.field(this, select.attr("field")));
	}

	override function edit2(ctx:hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<category("Look At")>
				<select([]) label="Target">
				</select>
				<line label="Lock Axis">
					<slider label="X" id="lockAxisX" field={lockAxis[0]}/>
					<slider label="Y" id="lockAxisY" field={lockAxis[1]}/>
					<slider label="Z" id="lockAxisZ" field={lockAxis[2]}/>
				</line>
				<checkbox field={faceTargetForward}/>
				<checkbox field={constantScreenSize}/>
			</category>
		);
	}
	#end

	static var _ = Prefab.register("lookAt", LookAt);
}