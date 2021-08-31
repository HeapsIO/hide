package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Fract")
@description("The fractional part of X")
@width(80)
@group("Math")
class Fract extends ShaderFunction {

	@input("X") var x = SType.Number;

	public function new() {
		super(Fract);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}

}