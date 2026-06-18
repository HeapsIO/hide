package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Luminance")
@description("The output is the luminance of the rgb color")
@width(80)
@group("Math")
class Luminance extends ShaderNodeHxsl {
	static var SRC = {
        @:import h3d.shader.ColorSpaces;

		@sginput(0.0) var rgb : Vec3;
		@sgoutput var output : Float;
		function fragment() {
			output = rgb2luminance(rgb);
		}
	};

}