package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Cosinus")
@description("The output is the arc cosinus of A")
@width(80)
@group("Math")
class Acos extends ShaderFunction {

	@input("A") var a = SType.Float;

	public function new() {
		super(Acos);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}