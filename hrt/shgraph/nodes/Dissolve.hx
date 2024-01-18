package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Dissolve")
@description("Dissolve input")
@width(150)
@group("Math")
class Dissolve extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(1.0) var channel : Float;
		@sginput(1.0) var progress : Float;
		@sginput(0.0) var saturation : Float;
		@sginput(1.0) var width : Float;
		@sgoutput var output : Float;

		function fragment() {
			var edge = mix(1.0 + width, -width, progress);
			var ramp = saturate((1.0 + saturation) * (width - abs(edge - channel)) / width);
			output = channel * ramp;
		}
	};
}