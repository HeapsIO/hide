package hrt.shader;

/**
	Shader that displays a grid background on 2d elements where they are
	transparent to help visualize the alpha channel.
**/
class PreviewShaderAlpha extends hxsl.Shader {
	static var SRC = {
		@param var scale: Vec2 = vec2(16.0);
		@param var split: Float = 0.0;

		var absolutePosition : Vec4;
		var calculatedUV : Vec2;

		var pixelColor : Vec4;

		function fragment() {
			if (calculatedUV.x >= split) {
				var cb = floor(mod(absolutePosition.xy / scale, vec2(2.0)));
				var check = mod(cb.x + cb.y, 2.0);
				var color = check >= 1.0 ? vec3(0.22) : vec3(0.44);
				pixelColor.rgb = mix(color, pixelColor.rgb, pixelColor.a);
			}
			pixelColor.a = 1.0;
		}
	}
}