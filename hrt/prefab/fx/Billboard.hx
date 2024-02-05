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
		qRot.initDirection(fwd, camera.up);

		absPos.tx = tmpMat.tx;
		absPos.ty = tmpMat.ty;
		absPos.tz = tmpMat.tz;
	}
}

@:allow(hrt.prefab.fx.Billboard.BillboardInstance)
class Billboard extends Object3D {

	override function makeObject(parent3d: h3d.scene.Object) {
		return new BillboardObject(parent3d);
	}

	#if editor
	override function getHideProps():hide.prefab.HideProps {
		return {
			icon: "cog",
			name: "Billboard"
		};
	}
	#end

	static var _ = Prefab.register("billboard", Billboard);
}