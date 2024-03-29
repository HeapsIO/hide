package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Cosinus")
@description("The output is the arc cosinus of A")
@width(80)
@group("Math")
class Acos extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = acos(a);
		}
	};

}