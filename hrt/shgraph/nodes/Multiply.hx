package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Multiply")
@description("The output is the result of A * B")
@width(80)
@group("Operation")
class Multiply extends Operation {

	public function new() {
		super(OpMult);
	}

}