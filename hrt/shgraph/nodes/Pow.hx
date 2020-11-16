package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Pow")
@description("The output is the result of x ^ b")
@width(80)
@group("Math")
class Pow extends ShaderFunction {

	@input("x") var x = SType.Number;
	@input("p", true) var p = SType.Number;

	public function new() {
		super(Pow);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}
}