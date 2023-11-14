package hrt.prefab.fx;

@:access(hrt.prefab.fx.LookAt)
class BillboardObject extends h3d.scene.Object {
	var graphics:h3d.scene.Graphics;

	static var tmpMat = new h3d.Matrix();
	static var tmpVec = new h3d.Vector();

	override function syncRec(ctx) {
		posChanged = true;
		super.syncRec(ctx);
	}

	override function calcAbsPos() {
		super.calcAbsPos();

		var camera = getScene().camera;
		if (camera == null)
			return;

		tmpMat.load(absPos);

		var fwd = tmpVec;
		fwd.load(camera.target.sub(camera.pos));
		fwd.normalize();
		qRot.initDirection(fwd);

		absPos.tx = tmpMat.tx;
		absPos.ty = tmpMat.ty;
		absPos.tz = tmpMat.tz;
	}
}

@:allow(hrt.prefab.fx.Billboard.BillboardInstance)
class Billboard extends Object3D {
	public function new(?parent) {
		super(parent);
		type = "billboard";
	}

	override function updateInstance(ctx:hrt.prefab.Context, ?propName:String) {
		super.updateInstance(ctx, propName);
	}

	override function makeInstance(ctx:Context) {
		ctx = ctx.clone(this);
		ctx.local3d = new BillboardObject(ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function getHideProps():HideProps {
		return {
			icon: "cog",
			name: "Billboard"
		};
	}
	#end

	static var _ = Library.register("billboard", Billboard);
}