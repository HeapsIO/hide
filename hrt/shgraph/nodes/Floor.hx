package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Floor")
@description("The nearest integer less than or equal to X")
@width(80)
@group("Math")
class Floor extends ShaderFunction {

	@input("x") var x = SType.Number;

	public function new() {
		super(Floor);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}

}