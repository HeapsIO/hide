package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Pow")
@description("The output is the result of x ^ b")
@width(80)
@group("Math")
class Pow extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = pow(a,b);
		}
	};

}