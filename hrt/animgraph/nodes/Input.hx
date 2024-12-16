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

	@:s var path : String = "character/Kobold01/Anim_attack01.FBX";

	override function getSize():Int {
		return Node.SIZE_BIG;
	}

	override function getBones(ctx: hrt.animgraph.nodes.AnimNode.GetBoneContext):Map<String, Int> {
		proxy = new AnimProxy();
		anim = hxd.res.Loader.currentInstance.load(path).toModel().toHmd().loadAnimation().createInstance(proxy);

		var map : Map<String, Int> = [];
		for (id => obj in anim.getObjects()) {
			map.set(obj.objectName, id);
		}
		return map;
	}

	override function tick(dt: Float) {
		anim.update(dt);
		@:privateAccess anim.isSync = false;
	}

	override function getBoneTransform(id: Int, matrix: h3d.Matrix, ctx: AnimNode.GetBoneTransformContext) {
		// todo : add sync outside the getBoneMatrix to avoid checks
		@:privateAccess
		if (!anim.isSync) {
			anim.sync(true);
			anim.isSync = true;
		}
		matrix.load(anim.getObjects()[id].targetObject.defaultTransform);
	}

	override function getPropertiesHTML(width:Float):Array<hide.Element> {
		var elts = super.getPropertiesHTML(width);

		var wrapper = new hide.Element("<input-wrapper></input-wrapper>");
		wrapper.height("20px");

		var fileSelect = new hide.comp.FileSelect(["fbx"], wrapper);
		fileSelect.path = path;
		fileSelect.onChange = () -> {
			path = fileSelect.path;
		}
		elts.push(wrapper);

		return elts;
	}
}