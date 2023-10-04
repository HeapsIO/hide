package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Pow")
@description("The output is the result of x ^ b")
@width(80)
@group("Math")
class Pow extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput(0.0) var b : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = pow(a,b);
		}
	};

}