package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Lerp")
@description("Linear interpolation between Min and Max using A")
@width(80)
@group("Math")
class Lerp extends ShaderFunction {

	@input("min") var x = SType.Number;
	@input("max") var y = SType.Number;
	@input("A") var a = SType.Number;

	public function new() {
		super(Mix);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty() && y != null && !y.isEmpty())
			addOutput("output", x.getVar(y.getType()).t);
		else if (x != null && !x.isEmpty() )
			addOutput("output", x.getType());
		else if (y != null && !y.isEmpty())
			addOutput("output", y.getType());
		else
			removeOutput("output");
	}

}