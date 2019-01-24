package hide.prefab.fx;


@:access(hide.prefab.fx.LookAt)
class LookAtInstance {
	var object: h3d.scene.Object;
	var target: h3d.scene.Object;
	var definition: LookAt;

	public function new(def, obj, target) {
		this.definition = def;
		this.object = obj;
		this.target = target;
	}

	static var tmpMat = new h3d.Matrix();
	static var deltaVec = new h3d.Vector();
	static var lockAxis = new h3d.Vector();
	static var tempQ = new h3d.Quat();
	public function apply() {
		if(object == null || object.getScene() == null)
			return;

		var lookAtPos =
			if(target != null)
				target.getAbsPos().getPosition();
			else
				object.getScene().camera.pos;

		deltaVec.load(lookAtPos.sub(object.getAbsPos().getPosition()));
		if(deltaVec.lengthSq() < 0.001)
			return;

		tmpMat.load(object.parent.getAbsPos());
		tmpMat.invert();
		var invParentQ = tempQ;
		invParentQ.initRotateMatrix(tmpMat);

		if(definition.lockAxis != null) {
			lockAxis.set(definition.lockAxis[0], definition.lockAxis[1], definition.lockAxis[2]);
			if(lockAxis.lengthSq() > 0.001) {
				var targetOnPlane = h3d.col.Plane.fromNormalPoint(lockAxis.toPoint(), new h3d.col.Point()).project(deltaVec.toPoint()).toVector();
				targetOnPlane.normalize();
				var frontAxis = new h3d.Vector(1, 0, 0);
				var angle = hxd.Math.acos(frontAxis.dot3(targetOnPlane));

				var cross = frontAxis.cross(deltaVec);
				if(lockAxis.dot3(cross) < 0)
					angle = -angle;

				var q = object.getRotationQuat();
				q.initRotateAxis(lockAxis.x, lockAxis.y, lockAxis.z, angle);
				q.multiply(invParentQ, q);
				object.setRotationQuat(q);
				return;
			}
		}

		// Default look at
		h3d.Matrix.lookAtX(deltaVec, tmpMat);
		var q = object.getRotationQuat();
		q.initRotateMatrix(tmpMat);
		object.setRotationQuat(q);
	}
}

@:allow(hide.prefab.fx.LookAt.LookAtInstance)
class LookAt extends Prefab {

	var target(default,null) : String;
	var lockAxis: Array<Float> = [0,0,0];

	override public function load(v:Dynamic) {
		target = v.target;
		if(v.lockAxis != null)
			lockAxis = v.lockAxis;
	}

	override function save() {
		return {
			target : target,
			lockAxis: lockAxis
		};
	}

	override function updateInstance(ctx:hxd.prefab.Context, ?propName:String) {
		var targetObj = null;
		if(target != "camera")
			targetObj = ctx.locateObject(target);
		ctx.custom = new LookAtInstance(this, ctx.local3d, targetObj);
	}

	override function makeInstance( ctx : Context ) {
		ctx = ctx.clone(this);
		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function getHideProps() : HideProps {
		return {
			icon : "cog",
			name : "LookAt",
			allowParent : function(p) return p.to(Object3D) != null && p.getParent(FX) != null,
			allowChildren: function(s) return false
		};
	}

	override function edit(ctx:EditContext) {
		var group = new hide.Element('
		<div class="group" name="LookAt">
			<dl>
				<dt>Target</dt><dd><select field="target"><option value="">-- Choose --</option></select></dd>
			</dl>
		</div>');

		group.append(hide.comp.PropsEditor.makePropsList([
			{ name: "lockAxis", t: PVec(3), def: [1,0,0] }
		]));

		var props = ctx.properties.add(group ,this, function(_) { trace(this.lockAxis); });

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

	static var _ = hxd.prefab.Library.register("lookAt", LookAt);
}