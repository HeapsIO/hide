package hide.prefab.fx;


class LookAtInstance {
	var object: h3d.scene.Object;
	var target: h3d.scene.Object;
	public function new(obj, target) {
		this.object = obj;
		this.target = target;
	}

	static var tmpMat = new h3d.Matrix();
	static var tmpVec = new h3d.Vector();
	public function apply() {
		if(object == null || object.getScene() == null)
			return;

		var lookAtPos =
			if(target != null)
				target.getAbsPos().getPosition();
			else
				object.getScene().camera.pos;

		tmpVec.load(lookAtPos.sub(object.getAbsPos().getPosition()));
		if(tmpVec.lengthSq() < 0.001)
			return;
		h3d.Matrix.lookAtX(tmpVec, tmpMat);
		var q = object.getRotationQuat();
		q.initRotateMatrix(tmpMat);
		object.setRotationQuat(q);
	}
}

class LookAt extends Prefab {

	public var target(default,null) : String;

	override public function load(v:Dynamic) {
		target = v.target;
	}

	override function save() {
		return {
			target : target
		};
	}

	override function updateInstance(ctx:hxd.prefab.Context, ?propName:String) {
		var targetObj = null;
		if(target != "camera")
			targetObj = ctx.locateObject(target);
		ctx.custom = new LookAtInstance(ctx.local3d, targetObj);
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
		var props = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Target</dt><dd><select field="target"><option value="">-- Choose --</option></select>
			</dl>
		'),this, function(_) {

		});

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