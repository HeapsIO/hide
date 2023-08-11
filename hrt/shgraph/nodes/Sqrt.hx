package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sqrt")
@description("The output is the squre root A")
@width(80)
@group("Math")
@:keep
class Sqrt extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = sqrt(a);
		}
	};

}