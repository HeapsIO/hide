package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Add")
@description("The output is the result of A + B")
@width(80)
@group("Operation")
class Add extends Operation {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput(0.0) var b : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = a + b;
		}
	}

}