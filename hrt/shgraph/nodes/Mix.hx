package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Mix")
@description("Linear interpolation between A and B using Mix")
@width(80)
@group("Math")
class Mix extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sginput var fact : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = mix(a,b, fact);
		}
	};

}