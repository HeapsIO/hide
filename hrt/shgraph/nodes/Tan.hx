package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Tangent")
@description("The output is the tangent of A")
@width(80)
@group("Math")
class Tan extends  ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = tan(a);
		}
	};

}