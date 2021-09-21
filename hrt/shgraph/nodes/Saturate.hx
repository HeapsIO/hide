package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Saturate")
@description("Saturate input A")
@width(80)
@group("Math")
class Saturate extends ShaderFunction {

	@input("X") var x = SType.Number;

	public function new() {
		super(Saturate);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}

}