package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Tangent")
@description("The output is the tangent of A")
@width(80)
@group("Math")
class Tan extends ShaderFunction {

	@input("A") var a = SType.Float;

	public function new() {
		super(Tan);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}