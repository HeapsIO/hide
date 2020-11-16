package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Step")
@description("Generate a step function by comparing a[i] to edge[i]")
@width(80)
@group("Math")
class Step extends ShaderFunction {

	@input("edge") var edge = SType.Number;
	@input("a") var x = SType.Number;

	public function new() {
		super(Step);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty() && edge != null && !edge.isEmpty())
			addOutput("output", edge.getVar(x.getType()).t);
		else if (x != null && !x.isEmpty() )
			addOutput("output", x.getType());
		else if (edge != null && !edge.isEmpty())
			addOutput("output", edge.getType());
		else
			removeOutput("output");
	}

}