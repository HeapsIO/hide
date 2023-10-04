package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Mix")
@description("Linear interpolation between A and B using Mix")
@width(80)
@group("Math")
class Mix extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput(0.0) var b : Vec4;
		@sginput var fact : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = mix(a,b, fact);
		}
	};

}