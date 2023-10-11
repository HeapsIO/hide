package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Abs")
@description("The output is the result of |A|")
@width(80)
@group("Math")
class Abs extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = abs(a);
		}
	};

}