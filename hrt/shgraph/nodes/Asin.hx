package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Sinus")
@description("The output is the arc sinus of A")
@width(80)
@group("Math")
class Asin extends ShaderFunction {

	@input("A") var a = SType.Float;

	public function new() {
		super(Asin);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}