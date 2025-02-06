package hrt.animgraph.nodes;

import hrt.tools.MapUtils;
class AnimProxy extends h3d.scene.Object {
	var map : Map<String, h3d.scene.Object> = [];

	override function getObjectByName(name: String) {
		return MapUtils.getOrPut(map, name, new h3d.scene.Object(null));
	}
}

class Input extends AnimNode {
	var anim : h3d.anim.Animation;
	var proxy : AnimProxy;

	@:s var path : String = "";

	override function getBones(ctx: hrt.animgraph.nodes.AnimNode.GetBoneContext):Map<String, Int> {
		proxy = new AnimProxy();
		var pathToLoad = ctx.resolver(path);
		if (pathToLoad == null)
			return [];
		try {
			anim = hxd.res.Loader.currentInstance.load(pathToLoad).toModel().toHmd().loadAnimation().createInstance(proxy);
		} catch (e) {
			return [];
		}

		var map : Map<String, Int> = [];
		for (id => obj in anim.getObjects()) {
			map.set(obj.objectName, id);
		}
		return map;
	}

	override function tick(dt: Float) {
		if (anim == null)
			return;
		anim.update(dt);
		@:privateAccess anim.isSync = false;
	}

	override function getBoneTransform(id: Int, matrix: h3d.Matrix, ctx: AnimNode.GetBoneTransformContext) {
		// todo : add sync outside the getBoneMatrix to avoid checks
		if (anim == null) {
			matrix.load(ctx.getDefPose());
			return;
		}

		@:privateAccess
		if (!anim.isSync) {
			anim.sync(true);
			anim.isSync = true;
		}
		matrix.load(anim.getObjects()[id].targetObject.defaultTransform);
	}

	function setupAnimEvents() {
		if (anim != null) {
			anim.onEvent = onEvent;
		}
	}

	#if editor
	override function getPropertiesHTML(width:Float):Array<hide.Element> {
		var elts = super.getPropertiesHTML(width);

		var wrapper = new hide.Element("<input-wrapper></input-wrapper>");
		wrapper.height("20px");

		new hide.view.animgraph.AnimPicker(wrapper, getAnimEditor().undo, () -> path, (s) -> {
			path = s;
			getAnimEditor().refreshPreview();
		});
		elts.push(wrapper);

		return elts;
	}

	override function getSize():Int {
		return Node.SIZE_BIG;
	}
	#end
}