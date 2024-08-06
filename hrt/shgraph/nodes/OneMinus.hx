package hrt.shgraph.nodes;

using hxsl.Ast;

@name("One minus")
@description("Returns 1 - a")
@width(80)
@group("Math")
class OneMinus extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = 1.0 - a;
		}
	};

}