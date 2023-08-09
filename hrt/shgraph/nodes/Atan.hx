package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Tangent")
@description("The output is the arc tangent of A")
@width(80)
@group("Math")
class Atan extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = atan(a);
		}
	};
}