package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Clamp")
@description("Limits value between min and max")
@width(80)
@group("Math")
class Clamp extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput var min : Vec4;
		@sginput var max : Vec4;

		@sgoutput var output : Vec4;
		function fragment() {
			output = clamp(a, min, max);
		}
	};
}