package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Subtract")
@description("The output is the result of A - B")
@width(80)
@group("Operation")
class Subtract extends Operation {

	public function new() {
		super(OpSub);
	}

}