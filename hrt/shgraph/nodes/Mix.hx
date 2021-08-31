package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Mix")
@description("Linear interpolation between a and b using mix")
@width(80)
@group("Math")
class Mix extends ShaderFunction {

	@input("A") var x = SType.Number;
	@input("B") var y = SType.Number;
	@input("Mix") var a = SType.Number;

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