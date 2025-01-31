package hrt.animgraph.nodes;

using hrt.tools.MapUtils;


class GetBoneContext {
	public function new() {

	}

	public var targetObject:h3d.scene.Object;
	public var resolver : (path: String) -> Null<String>;
	public var modelCache : h3d.prim.ModelCache;
}

class GetBoneTransformContext {
	public function new() {

	}

	public function reset(target: hrt.animgraph.AnimGraphInstance.AnimGraphAnimatedObject) {
		defMatrix = null;
		targetObj = target;
	}

	var targetObj : hrt.animgraph.AnimGraphInstance.AnimGraphAnimatedObject;

	var tmpDefMatrix = new h3d.Matrix();
	var defMatrix : h3d.Matrix = null;

	/**
		In the decomposed format
	**/
	@:haxe.warning("-WInlineOptimizedField")
	public function getDefPose() : h3d.Matrix {
		if (defMatrix != null) return defMatrix;
		var m = if (targetObj.targetSkin != null) {
			targetObj.targetSkin.getSkinData().allJoints[targetObj.targetJoint].defMat ?? @:privateAccess h3d.anim.SmoothTransition.MZERO;
		} else {
			targetObj.targetObject.defaultTransform ?? @:privateAccess h3d.anim.SmoothTransition.MZERO;
		}
		Tools.decomposeMatrix(m, tmpDefMatrix);

		defMatrix = tmpDefMatrix;
		return defMatrix;
	}
}

/**
	An anim node outpus a animation that can be consumed as input parameter by other nodes
**/
class AnimNode extends Node {
	var numAnimInput : Int;
	var boneIdToAnimInputBone : Array<Int>;

	var onEvent : (String) -> Void;

	inline function getInputBoneId(boneId: Int, inputId: Int) {
		return boneId * numAnimInput + inputId;
	}

	public function getBones(ctx: GetBoneContext) : Map<String, Int> {
		// Default implementation for AnimNodes that takes multiple animation inputs and output one new animation
		var inputs = getInputs();
		numAnimInput = 0;
		for (inputId => input in inputs) {
			switch (input.type) {
				case TAnimation:
					numAnimInput++;
				default:
			}
		}

		var boneMap : Map<String, Int> = [];
		boneIdToAnimInputBone = [];
		var currentBoneId = 0;
		var currentInputId = 0;
		for (input in inputs) {
			switch (input.type) {
				case TAnimation:
					var anim : AnimNode = cast Reflect.getProperty(this, input.name);
					if (anim == null) {
						currentInputId ++;
						continue;
					}
					var animBones = anim.getBones(ctx);
					for (name => id in animBones) {
						var ourBoneId = boneMap.getOrPut(name, {
							currentBoneId++;
							for (i in 0...numAnimInput) {
								boneIdToAnimInputBone[getInputBoneId(currentBoneId, i)] = -1;
							}
							currentBoneId;
						});
						boneIdToAnimInputBone[getInputBoneId(ourBoneId, currentInputId)] = id;
					}
					currentInputId ++;
				default:
			}
		}

		return boneMap;
	}

	function getBoneTransform(boneId: Int, outMatrix: h3d.Matrix, ctx: GetBoneTransformContext) : Void {
	}

	#if editor

	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		info.playButton = {
			getActive: () -> {
				return this == @:privateAccess getAnimEditor().previewNode;
			},
			onClick: () -> {
				getAnimEditor().setPreview(this);
			}
		};
		return info;
	}
	#end
}