package hrt.animgraph.nodes;

using hrt.tools.MapUtils;


/**
	An anim node outpus a animation that can be consumed as input parameter by other nodes
**/
class AnimNode extends Node {
	var numAnimInput : Int;
	var boneIdToAnimInputBone : Array<Int>;

	inline function getInputBoneId(boneId: Int, inputId: Int) {
		return boneId * numAnimInput + inputId;
	}

	public function getBones() : Map<String, Int> {
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
					var animBones = anim.getBones();
					for (name => id in animBones) {
						var ourBoneId = boneMap.getOrPut(name, currentBoneId++);
						boneIdToAnimInputBone[getInputBoneId(ourBoneId, currentInputId)] = id;
					}
					currentInputId ++;
				default:
			}
		}

		return boneMap;
	}

	function getBoneTransform(boneId: Int, outMatrix: h3d.Matrix) : Void {
	}
}