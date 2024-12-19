package hrt.animgraph.nodes;

/**
	The result of this node can be used as an animation by other systems
**/
class Output extends AnimNode {

	@:input var a: AnimNode;

	override function tick(dt: Float) {
		// update out using inputs
	}

	override function getSize() : Int {
		return Node.SIZE_SMALL;
	}

	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		var animGraphEditor : hide.view.animgraph.AnimGraphEditor = cast editor.editor;
		info.playButton = {
			getActive: () -> {
				return @:privateAccess animGraphEditor.previewNode == null;
			},
			onClick: () -> {
				animGraphEditor.setPreview(null);
			}
		};
		return info;
	}

	override function getBones(ctx:hrt.animgraph.nodes.AnimNode.GetBoneContext):Map<String, Int> {
		return a.getBones(ctx);
	}

	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix, ctx:hrt.animgraph.nodes.AnimNode.GetBoneTransformContext) {
		return a.getBoneTransform(boneId, outMatrix, ctx);
	}
}