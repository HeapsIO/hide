package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Saturate")
@description("Saturate input A")
@width(80)
@group("Math")
class Saturate extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = saturate(a);
		}
	};

}