package hrt.shgraph.nodes;

using hxsl.Ast;

@name("RGB to HSL")
@description("Converts a rgb color to hsl (hue, saturation, lightness), all in [0, 1]")
@width(80)
@group("Math")
class RGBtoHSL extends ShaderNodeHxsl {
	static var SRC = {
		@:import h3d.shader.ColorSpaces;

		@sginput(0.0) var rgb : Vec3;
		@sgoutput var hsl : Vec3;
		function fragment() {
			hsl = rgb2hsl(rgb);
		}
	};

}
