package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Dissolve")
@description("Dissolve input")
@width(180)
@group("Math")
class Dissolve extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var rgba : Vec4;
		@sginput(calculatedUV) var uv : Vec2;
		@sginput var dissolveMap : Sampler2D;
		@sginput(0.5) var progress : Float;
		@sginput(0.5) var saturation : Float;
		@sginput(1.0) var width : Float;
		@sgoutput var output : Vec4;

		function fragment() {
			var pix = dissolveMap.get(uv);
			var edge = mix(1.0 + width, -width, progress);
			var ramp = saturate((1.0 + saturation) * (width - abs(edge - pix.r)) / width);
			output.rgb = rgba.rgb;
			output.a = rgba.a * ramp * pix.a;
		}
	};
}