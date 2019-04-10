package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Maximum")
@description("The output is the maximum between A and B")
@group("Math")
class Maximum extends ShaderFunction {

	@input("A") var a = SType.Number;
	@input("B") var b = SType.Number;

	public function new() {
		super(Max);
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