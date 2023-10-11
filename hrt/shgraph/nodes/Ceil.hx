package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Ceil")
@description("The nearest integer greater than or equal to X")
@width(80)
@group("Math")
class Ceil extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = ceil(a);
		}
	};
}