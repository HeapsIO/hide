package hrt.shader;

class GradientMap extends hxsl.Shader {
	static var SRC = {
		@const var USE_ALPHA : Bool;
		@param var gradient : Sampler2D;
		var pixelColor : Vec4;

		function fragment() {
			var t = USE_ALPHA ? pixelColor.a : dot(pixelColor.rgb*pixelColor.rgb, vec3(0.2126, 0.7152, 0.0722));
			pixelColor.rgb = gradient.get(vec2(t, 0.5)).rgb;
		}
	};
}