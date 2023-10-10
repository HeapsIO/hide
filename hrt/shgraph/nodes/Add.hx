package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Add")
@description("The output is the result of A + B")
@width(80)
@group("Operation")
class Add extends Operation {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = a + b;
		}
	}

}