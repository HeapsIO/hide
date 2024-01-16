package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Clamp")
@description("Limits value between min and max")
@width(80)
@group("Math")
class Clamp extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput var min : Dynamic;
		@sginput var max : Dynamic;

		@sgoutput var output : Dynamic;
		function fragment() {
			output = clamp(a, min, max);
		}
	};
}