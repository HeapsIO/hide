package hrt.animgraph.nodes;

class BlendPerBone extends AnimNode {
	@:input var a: AnimNode;
	@:input var b: AnimNode;

	@:s var targetBone : String = "Bip001 Spine1";

	override function getBones(ctx: hrt.animgraph.nodes.AnimNode.GetBoneContext) : Map<String, Int> {
		var map = super.getBones(ctx);

		for (bone => id in map.copy()) {
			var jointObject = Std.downcast(ctx.targetObject.getObjectByName(bone), h3d.scene.Skin.Joint);
			if (jointObject == null)
				continue;
			var skin = jointObject.skin.getSkinData();
			var joint = skin.namedJoints.get(jointObject.name);
			var found = false;
			while (joint != null) {
				if (joint.name == targetBone) {
					found = true;
					break;
				}
				joint = joint.parent;
			}

			// disable the bone in the first or second animation
			var inputId = found ? 0 : 1;
			boneIdToAnimInputBone[getInputBoneId(id, 1-inputId)] = -1;
			if (boneIdToAnimInputBone[getInputBoneId(id, inputId)] == -1) {
				map.remove(bone);
			}
		}
		return map;
	}

	override function getBoneTransform(boneId: Int, outMatrix: h3d.Matrix) : Void {
		for (animId in 0...2) {

			var animBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, animId)];
			if (animBoneId == -1)
				continue;
			var anim = animId == 0 ? a : b;
			anim.getBoneTransform(animBoneId, outMatrix);
			break;
		}
	}
}