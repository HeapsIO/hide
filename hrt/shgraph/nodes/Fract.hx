package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Fract")
@description("The fractional part of X")
@width(80)
@group("Math")
class Fract extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = fract(a);
		}
	};

}