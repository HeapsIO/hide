package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Invert")
@description("The output is 1 - in")
@width(80)
@group("Math")
class Invert extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = 1.0 - a;
		}
	};

}