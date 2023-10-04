package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Exp")
@description("The output is the result of exp(x)")
@width(80)
@group("Math")
class Exp extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = exp(a);
		}
	};

}