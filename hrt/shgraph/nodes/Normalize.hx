package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Normalize")
@description("The output is the result of normalize(x)")
@width(80)
@group("Math")
class Normalize extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = normalize(a);
		}
	};

}