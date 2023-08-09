package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Abs")
@description("The output is the result of |A|")
@width(80)
@group("Math")
class Abs extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = abs(a);
		}
	};

}