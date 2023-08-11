package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Min")
@description("The output is the minimum between A and B")
@width(80)
@group("Math")
class Min extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sginput var b : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = min(a,b);
		}
	};

}