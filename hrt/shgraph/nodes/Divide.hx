package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Divide")
@description("The output is the result of A / B")
@width(80)
@group("Math")
class Divide extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(1.0) var a : Dynamic;
		@sginput(1.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = a / b;
		}
	};

}