package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Exp")
@description("The output is the result of exp(x)")
@width(80)
@group("Math")
class Exp extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = exp(a);
		}
	};

}