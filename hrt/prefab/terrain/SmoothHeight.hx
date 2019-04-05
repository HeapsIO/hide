package hide.prefab.terrain;

class SmoothHeight extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var prevHeight : Sampler2D;
		@param var prevHeightResolution : Vec2;
		@param var strengthTex : Sampler2D;
		@param var range : Int;

		function fragment() {
			var height = prevHeight.get(calculatedUV).r;
			var strength = strengthTex.get(calculatedUV).r;
			var pixelSize =  1.0 / prevHeightResolution;

			var averageHeight = 0.0;
			for( i in -range ... range + 1 ){
				for( j in -range ... range + 1){
					averageHeight += prevHeight.getLod(calculatedUV + pixelSize * vec2(i,j), 0).r;
				}
			}
			averageHeight /= (range * 2 + 1) * (range * 2 + 1);
			pixelColor = vec4(mix(height, averageHeight, clamp(strength,0,1)));
		}
	}
}
