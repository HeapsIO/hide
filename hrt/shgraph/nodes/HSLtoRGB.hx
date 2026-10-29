package hrt.shgraph.nodes;

using hxsl.Ast;

@name("HSL to RGB")
@description("Converts a hsl color (hue, saturation, lightness, all in [0, 1]) to rgb")
@width(80)
@group("Math")
class HSLtoRGB extends ShaderNodeHxsl {
	static var SRC = {
		@sginput(0.0) var hsl : Vec3;
		@sgoutput var rgb : Vec3;
		function fragment() {
			var c = clamp(abs(mod(hsl.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
			rgb = hsl.z + hsl.y * (c - 0.5) * (1.0 - abs(2.0 * hsl.z - 1.0));
		}
	};

}
