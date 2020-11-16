package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Normalize")
@description("The output is the result of normalize(x)")
@width(80)
@group("Math")
class Normalize extends ShaderFunction {

	@input("x") var x = SType.Number;

	public function new() {
		super(Normalize);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}
}