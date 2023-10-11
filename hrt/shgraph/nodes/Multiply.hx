package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Multiply")
@description("The output is the result of A * B")
@width(80)
@group("Operation")
class Multiply extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(1.0) var a : Dynamic;
		@sginput(1.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = a * b;
		}
	}
}