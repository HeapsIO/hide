package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Modulo")
@description("The output is the result of X modulo MOD")
@width(80)
@group("Math")
class Mod extends ShaderFunction {

	@input("x") var x = SType.Float;
	@input("mod") var mod = SType.Float;

	public function new() {
		super(Mod);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}

}