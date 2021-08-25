package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Length")
@description("")
@width(80)
@group("Math")
class Length extends ShaderFunction {

	@input("A") var a = SType.Vec2;

	public function new() {
		super(Length);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", TFloat);
		else
			removeOutput("output");
	}

}