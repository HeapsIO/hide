package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sign")
@description("Returns 1.0 if a[i] is positive, -1.0 otherwise")
@width(80)
@group("Math")
class Sign extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = sign(a);
		}
	};
}