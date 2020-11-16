package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Ceil")
@description("The nearest integer greater than or equal to X")
@width(80)
@group("Math")
class Ceil extends ShaderFunction {

	@input("x") var x = SType.Number;

	public function new() {
		super(Ceil);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}

}