package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Max")
@description("The output is the maximum between A and B")
@width(80)
@group("Math")
class Max extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = max(a,b);
		}
	};

}