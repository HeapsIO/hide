package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Divide")
@description("The output is the result of A / B")
@width(80)
@group("Operation")
class Divide extends Operation {

	public function new() {
		super(OpDiv);
	}

}