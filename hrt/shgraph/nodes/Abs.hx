package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Abs")
@description("The output is the result of |A|")
@group("Math")
class Abs extends ShaderFunction {

	@input("A") var a = SType.Number;

	public function new() {
		super(Abs);
	}

	override public function computeOutputs() {
		if (a != null && !a.isEmpty())
			addOutput("output", a.getType());
		else
			removeOutput("output");
	}

}