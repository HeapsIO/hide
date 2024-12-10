package hrt.animgraph.nodes;

using hrt.tools.MapUtils;


class GetBoneContext {
	public function new() {

	}

	public var targetObject:h3d.scene.Object;
}

/**
	An anim node outpus a animation that can be consumed as input parameter by other nodes
**/
class AnimNode extends Node {
	var numAnimInput : Int;
	var boneIdToAnimInputBone : Array<Int>;

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
					if (anim == null)
						continue;
					var animBones = anim.getBones(ctx);
					for (name => id in animBones) {
						var ourBoneId = boneMap.getOrPut(name, {
							currentBoneId++;
							for (i in 0...numAnimInput) {
								boneIdToAnimInputBone[getInputBoneId(currentBoneId, i)] = -1;
							}
							currentBoneId;
						});
						boneIdToAnimInputBone[getInputBoneId(ourBoneId, currentInputId)] = id; // we offset the id by one to differientate the 0 from the uninitialized entires in the array
					}
					currentInputId ++;
				default:
			}
		}

		return boneMap;
	}

	function getBoneTransform(boneId: Int, outMatrix: h3d.Matrix) : Void {
	}

	#if editor

	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		var animGraphEditor : hide.view.animgraph.AnimGraphEditor = cast editor.editor;
		info.previewButton = {
			getEnabled: () -> {
				return this == @:privateAccess animGraphEditor.previewNode;
			},
			onClick: () -> {
				animGraphEditor.setPreview(this);
			}
		};
		return info;
	}
	#end
}