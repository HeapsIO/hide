package hrt.prefab2.fx;


@:access(hrt.prefab2.fx.LookAt)
class LookAtObject extends h3d.scene.Object {
	var target: h3d.scene.Object;
	var definition: LookAt;

	public function new(parent, def) {
		super(parent);
		this.definition = def;
	}

	static var tmpMat = new h3d.Matrix();
	static var deltaVec = new h3d.Vector();
	static var lookAtPos = new h3d.Vector();
	static var lockAxis = new h3d.Vector();
	static var tempQ = new h3d.Quat();

	override function syncRec( ctx ) {
		posChanged = true;
		super.syncRec(ctx);
	}

	override function calcAbsPos() {
		if(target != null)
			lookAtPos = target.getAbsPos().getPosition();
		else {
			if(getScene() == null || getScene().camera == null) return;
			lookAtPos.load(getScene().camera.pos);
			lookAtPos.w = 1;
		}

		super.calcAbsPos();
		deltaVec.load(lookAtPos.sub(absPos.getPosition()));
		if(deltaVec.lengthSq() < 0.001)
			return;

		if(definition.lockAxis != null)
			lockAxis.set(definition.lockAxis[0], definition.lockAxis[1], definition.lockAxis[2]);
		else
			lockAxis.set();

		if(lockAxis.lengthSq() > 0.001) {
			tmpMat.load(parent.getAbsPos());
			tmpMat.invert();
			lookAtPos.transform(tmpMat);
			deltaVec.set(lookAtPos.x - x, lookAtPos.y - y, lookAtPos.z - z);

			var invParentQ = tempQ;
			invParentQ.initRotateMatrix(tmpMat);

			var targetOnPlane = h3d.col.Plane.fromNormalPoint(lockAxis.toPoint(), new h3d.col.Point()).project(deltaVec.toPoint()).toVector();
			targetOnPlane.normalize();
			var frontAxis = new h3d.Vector(1, 0, 0);
			var angle = hxd.Math.acos(frontAxis.dot(targetOnPlane));

			var cross = frontAxis.cross(deltaVec);
			if(lockAxis.dot(cross) < 0)
				angle = -angle;

			var q = getRotationQuat();
			q.initRotateAxis(lockAxis.x, lockAxis.y, lockAxis.z, angle);
			q.normalize();
			setRotationQuat(q);
			super.calcAbsPos();
		}
		else
		{
			tmpMat.load(absPos);
			var scale = tmpMat.getScale();
			qRot.initDirection(deltaVec);
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

@:allow(hrt.prefab2.fx.LookAt.LookAtInstance)
class LookAt extends Object3D {

	@:s var target(default,null) : String;
	@:s var lockAxis: Array<Float> = [0,0,0];

	override function updateInstance(?propName:String) {
		super.updateInstance(propName);
		var targetObj = null;
		if(target != "camera")
			targetObj = locateObject(target);
	}

	override function makeObject3d(parent3d:h3d.scene.Object):h3d.scene.Object {
		return new LookAtObject(parent3d, this);
	}

	#if editor
	override function getHideProps() : hide.prefab2.HideProps {
		return {
			icon : "cog",
			name : "LookAt"
		};
	}

	override function edit(ctx:hide.prefab2.EditContext) {
		super.edit(ctx);
		var group = new hide.Element('
		<div class="group" name="LookAt">
			<dl>
				<dt>Target</dt><dd><select field="target"><option value="">-- Choose --</option></select></dd>
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
	#end

	static var _ = Prefab.register("lookAt", LookAt);
}