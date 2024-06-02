package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Modulo")
@description("The output is the result of X modulo MOD")
@width(80)
@group("Math")
class Mod extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(1.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = mod(a,b);
		}
	};

}