package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Cross")
@description("The output is the cross product of a and b")
@width(80)
@group("Math")
class Cross extends ShaderFunction {

	@input("a") var a = SType.Number;
	@input("b") var b = SType.Number;

	public function new() {
		super(Cross);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty() && b != null && !b.isEmpty())
			addOutput("output", a.getVar(b.getType()).t);
		else if (a != null && !a.isEmpty() )
			addOutput("output", a.getType());
		else if (b != null && !b.isEmpty())
			addOutput("output", b.getType());
		else
			removeOutput("output");
	}
}