package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Minimum")
@description("The output is the minimum between A and B")
@group("Math")
class Minimum extends ShaderFunction {

	@input("A") var a = SType.Number;
	@input("B") var b = SType.Number;

	public function new() {
		super(Min);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else if (b != null && !b.isEmpty())
			addOutput("output", b.getType());
		else
			removeOutput("output");
	}

}