package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Dissolve")
@description("Dissolve input")
@width(180)
@group("Math")
class Dissolve extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var rgba : Vec4;
		@sginput var dissolveMap : Vec4;
		@sginput(0.5) var progress : Float;
		@sginput(0.5) var saturation : Float;
		@sginput(1.0) var width : Float;
		@sgoutput var output : Vec4;

		function fragment() {
			var edge = mix(1.0 + width, -width, progress);
			var ramp = saturate((1.0 + saturation) * (width - abs(edge - dissolveMap.r)) / width);
			output.rgb = rgba.rgb;
			output.a = rgba.a * ramp * dissolveMap.a;
		}
	};
}