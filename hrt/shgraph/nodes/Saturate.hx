package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Saturate")
@description("Saturate input A")
@width(80)
@group("Math")
class Saturate extends ShaderFunction {

	@input("A") var a = SType.Float;

	public function new() {
		super(Saturate);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}