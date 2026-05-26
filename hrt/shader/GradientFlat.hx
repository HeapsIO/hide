package hrt.shader;

class GradientFlat extends hxsl.Shader {
	static var SRC = {
		@const var USE_SOURCE_UV : Bool = false;
		@param var amount : Float = 1.0;
		@param var gradient : Sampler2D;

		@input var input : {
			var uv : Vec2;
		};

		var calculatedUV : Vec2;
		var pixelColor : Vec4;

		function __init__() : Void {
			calculatedUV = input.uv;
		}
		function fragment() {
			var gradientVal = gradient.get(USE_SOURCE_UV ? input.uv : calculatedUV);
			pixelColor.rgb = mix(pixelColor.rgb, gradientVal.rgb, amount);
		}
	}
}