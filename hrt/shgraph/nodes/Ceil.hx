package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Ceil")
@description("The nearest integer greater than or equal to X")
@width(80)
@group("Math")
class Ceil extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = ceil(a);
		}
	};
}