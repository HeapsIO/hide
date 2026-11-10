package hrt.shgraph.nodes;

using hxsl.Ast;

@name("HSL to RGB")
@description("Converts a hsl color (hue, saturation, lightness, all in [0, 1]) to rgb")
@width(80)
@group("Math")
class HSLtoRGB extends ShaderNodeHxsl {
	static var SRC = {
		@:import h3d.shader.ColorSpaces;

		@sginput(0.0) var hsl : Vec3;
		@sgoutput var rgb : Vec3;
		function fragment() {
			rgb = hsl2rgb(hsl);
		}
	};

}
