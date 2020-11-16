package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Min")
@description("The output is the minimum between A and B")
@width(80)
@group("Math")
class Min extends ShaderFunction {

	@input("A") var a = SType.Number;
	@input("B") var b = SType.Number;

	public function new() {
		super(Min);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else if (b != null && !b.isEmpty())
			addOutput("output", b.getType());
		else
			removeOutput("output");
	}

}