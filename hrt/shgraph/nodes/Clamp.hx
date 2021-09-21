package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Clamp")
@description("Limits value between min and max")
@width(80)
@group("Math")
class Clamp extends ShaderFunction {

	@input("X") var x = SType.Number;
	@input("Min", true) var min = SType.Number;
	@input("Max", true) var max = SType.Number;

	public function new() {
		super(Clamp);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}
}