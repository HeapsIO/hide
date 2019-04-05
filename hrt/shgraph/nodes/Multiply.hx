package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Multiply")
@description("The output is the result of A * B")
@group("Operation")
class Multiply extends Operation {

	public function new() {
		super(OpMult);
	}

}