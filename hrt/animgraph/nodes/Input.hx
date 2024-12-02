package hrt.animgraph.nodes;

using hrt.tools.MapUtils;
class AnimProxy extends h3d.scene.Object {
	var map : Map<String, h3d.scene.Object> = [];

	override function getObjectByName(name: String) {
		return map.getOrPut(name, new h3d.scene.Object(null));
	}
}

class Input extends AnimNode {
	var anim : h3d.anim.Animation;
	var proxy : AnimProxy;

	override function getSize():Int {
		return Node.SIZE_SMALL;
	}

	override function getBones():Map<String, Int> {
		proxy = new AnimProxy();
		anim = hxd.res.Loader.currentInstance.load("character/Kobold01/Anim_attack01.FBX").toModel().toHmd().loadAnimation().createInstance(proxy);

		var map : Map<String, Int> = [];
		for (id => obj in anim.getObjects()) {
			trace(obj.objectName, id);
			map.set(obj.objectName, id);
		}
		return map;
	}

	override function tick(dt: Float) {
		anim.update(dt);
		@:privateAccess anim.isSync = false;
	}

	override function getBoneTransform(id: Int, matrix: h3d.Matrix) {
		// todo : add sync outside the getBoneMatrix to avoid checks
		@:privateAccess
		if (!anim.isSync)
			anim.sync();
		matrix.load(anim.getObjects()[id].targetObject.defaultTransform);
	}
}