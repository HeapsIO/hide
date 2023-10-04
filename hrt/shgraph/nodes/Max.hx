package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Max")
@description("The output is the maximum between A and B")
@width(80)
@group("Math")
class Max extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput(0.0) var b : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = max(a,b);
		}
	};

}