package hrt.shader;

class Bloom extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var texture : Sampler2D;
		@param var threshold : Float;
		@param var intensity : Float;
		@param var colorMatrix : Mat4;

		function fragment() {
			pixelColor = texture.get(calculatedUV);
			var lum = pixelColor.rgb.dot(vec3(0.2126, 0.7152, 0.0722));
			if( lum < threshold ) pixelColor.rgb = vec3(0.) else pixelColor.rgb *= (lum - threshold) / lum;
			pixelColor.rgb *= intensity;
			pixelColor.rgb = (vec4(pixelColor.rgb,1.) * colorMatrix).rgb;
		}

	};

}