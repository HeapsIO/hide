package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Smooth Step")
@description("Linear interpolation between A and B using Mix")
@width(100)
@group("Math")
class SmoothStep extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sginput var fact : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = smoothstep(a,b, fact);
		}
	};

}