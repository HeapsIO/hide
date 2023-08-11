package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Floor")
@description("The nearest integer less than or equal to X")
@width(80)
@group("Math")
class Floor extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = floor(a);
		}
	};

}