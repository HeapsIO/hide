package hrt.animgraph;

@:access(hrt.animgraph.AnimGraph)
class AnimGraphInstance extends h3d.anim.Animation {
	var animGraph : AnimGraph;

	function new(animGraph:AnimGraph) {
		super(animGraph.name, 1000, 1/60.0);
		this.animGraph = animGraph;
	}
}