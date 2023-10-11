package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Floor")
@description("The nearest integer less than or equal to X")
@width(80)
@group("Math")
class Floor extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = floor(a);
		}
	};

}