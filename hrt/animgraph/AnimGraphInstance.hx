package hrt.animgraph;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphInstance extends h3d.anim.Animation {
	var animGraph : AnimGraph;
	var outputId : Int = -1;

	function new(animGraph:AnimGraph) {
		super(animGraph.name, 1000, 1/60.0);
		this.animGraph = animGraph;
		this.outputId = Lambda.find(animGraph.nodes, (node) -> Std.downcast(node, hrt.animgraph.nodes.Output) == null)?.id ?? -1;
	}

	override function clone(?target: h3d.anim.Animation) : h3d.anim.Animation {
		if (target != null) throw "Unexpected";
		var inst = super.clone(new AnimGraphInstance(cast animGraph.clone()));
		return inst;
	}

	override function update(dt:Float):Float {
		var dt = super.update(dt);
		if (outputId == -1)
			return;

		for (node in animGraph.nodes) {
			node.tickedThisFrame = false;
		}

		var finalNode : hrt.animgraph.nodes.Output = cast animGraph.nodes.get(outputId);
		tickRec(finalNode);

		return dt;
	}

	function tickRec(node: hrt.animgraph.Node, dt: Float) {
		var inputs = node.getInputs();

		for (inputId => edge in node.inputEdges) {
			if (edge == null) continue;
			var outputNode = animGraph.nodes.get(edge.nodeTarget);
			if (!outputNode.tickedThisFrame) {
				tickRec(outputNode, dt);
			}
			var outputs = outputNode.getOutputs();
			var output = outputs[edge.nodeOutputIndex];
			Reflect.setField(node, inputs[inputId].name, Reflect.getField(outputNode, output.name));
		}

		node.tick();
		node.tickedThisFrame = true;
	}
}