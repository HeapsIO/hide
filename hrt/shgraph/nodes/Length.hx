package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Length")
@description("")
@width(80)
@group("Math")
class Length extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sgoutput var output : Float;
		function fragment() {
			output = length(a);
		}
	};

}