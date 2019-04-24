package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Add")
@description("The output is the result of A + B")
@width(80)
@group("Operation")
class Add extends Operation {

	public function new() {
		super(OpAdd);
	}

}