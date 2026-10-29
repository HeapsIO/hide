package hrt.shgraph.nodes;

using hxsl.Ast;

@name("RGB to HSL")
@description("Converts a rgb color to hsl (hue, saturation, lightness), all in [0, 1]")
@width(80)
@group("Math")
class RGBtoHSL extends ShaderNodeHxsl {
	static var SRC = {
		@sginput(0.0) var rgb : Vec3;
		@sgoutput var hsl : Vec3;
		function fragment() {
			var K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			var p = mix(vec4(rgb.bg, K.wz), vec4(rgb.gb, K.xy), step(rgb.b, rgb.g));
			var q = mix(vec4(p.xyw, rgb.r), vec4(rgb.r, p.yzx), step(p.x, rgb.r));
			var d = q.x - min(q.w, q.y); // chroma = max - min
			var e = 1.0e-8;
			var h = abs(q.z + (q.w - q.y) / (6.0 * d + e));
			var l = q.x - d * 0.5;
			var s = d / max(1.0 - abs(2.0 * l - 1.0), e);
			hsl = vec3(h, s, l);
		}
	};

}
