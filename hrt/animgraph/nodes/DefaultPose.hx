package hrt.animgraph.nodes;

class DefaultPose extends AnimNode {

	var object = h3d.scene.Object;
	var objects : Array<{?object: h3d.scene.Object, ?skin: h3d.scene.Skin, ?joint: Int, ?matDecomposed: h3d.Matrix}> = [];

	override function getBones(ctx:hrt.animgraph.nodes.AnimNode.GetBoneContext):Map<String, Int> {
		objects = [];
		var bones : Map<String, Int> = [];

		var targetObjects = ctx.targetObject.findAll((f) -> f);
		for (obj in targetObjects) {
			var index = objects.length;
			objects.push({object: obj});
			bones.set(obj.name, index);
		}

		var skins = ctx.targetObject.findAll((f) -> Std.downcast(f, h3d.scene.Skin));
		for (skin in skins) {
			for (joint in skin.getSkinData().allJoints) {
				var index = objects.length;
				objects.push({skin: skin, joint: joint.index});
				bones.set(joint.name, index);
			}
		}
		return bones;
	}

	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix, ctx:hrt.animgraph.nodes.AnimNode.GetBoneTransformContext) {
		var bone = objects[boneId];
		if (bone.matDecomposed == null) {
			var m = bone.skin != null ? bone.skin.getSkinData().allJoints[bone.joint].defMat : bone.object.defaultTransform;
			bone.matDecomposed = new h3d.Matrix();

			Tools.splitMatrix(m, bone.matDecomposed);
		}
		outMatrix.load(bone.matDecomposed);
	}
}