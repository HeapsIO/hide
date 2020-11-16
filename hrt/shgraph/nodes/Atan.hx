package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Tangent")
@description("The output is the arc tangent of A")
@width(80)
@group("Math")
class Atan extends ShaderFunction {

	@input("A") var a = SType.Float;

	public function new() {
		super(Atan);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}