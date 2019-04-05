package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Divide")
@description("The output is the result of A / B")
@group("Operation")
class Divide extends Operation {

	public function new() {
		super(OpDiv);
	}

}