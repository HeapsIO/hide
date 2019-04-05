package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Subtract")
@description("The output is the result of A - B")
@group("Operation")
class Subtract extends Operation {

	public function new() {
		super(OpSub);
	}

}