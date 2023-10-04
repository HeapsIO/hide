package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Divide")
@description("The output is the result of A / B")
@width(80)
@group("Operation")
class Divide extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(1.0) var a : Vec4;
		@sginput(1.0) var b : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = a / b;
		}
	};

}