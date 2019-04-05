package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Add")
@description("The output is the result of A + B")
@group("Operation")
class Add extends Operation {

	public function new() {
		super(OpAdd);
	}

}