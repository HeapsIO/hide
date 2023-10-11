package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Saturate")
@description("Saturate input A")
@width(80)
@group("Math")
class Saturate extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = saturate(a);
		}
	};

}