package hrt.shader;

class GradientMap extends hxsl.Shader {
	static var SRC = {
		@const var USE_ALPHA : Bool;
		@param var gradient : Sampler2D;
		var pixelColor : Vec4;

		function fragment() {
			var t = USE_ALPHA ? pixelColor.a : dot(pixelColor.rgb*pixelColor.rgb, vec3(0.2126, 0.7152, 0.0722));

			// Force clamping values (compatibility for gradients that are now in repeat mode by default)
			var uv2 = vec2(t, 0.5);
			var size = gradient.size();
			uv2 = clamp(uv2, 0.5 / size, (size - vec2(0.5)) / size);

			pixelColor.rgb = gradient.get(uv2).rgb;
		}
	};
}