package hrt.shader;

class HeightFog extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var startHeight : Float;
		@param var endHeight : Float;
		@param var startOpacity : Float;
		@param var endOpacity: Float;
		@param var startColorHeight : Float;
		@param var endColorHeight : Float;
		@param var startColor : Vec3;
		@param var endColor : Vec3;

		@ignore @param var depthTexture : Channel;
		@ignore @param var cameraPos : Vec3;
		@ignore @param var cameraInverseViewProj : Mat4;

		function getPosition( uv: Vec2 ) : Vec3 {
			var depth = depthTexture.get(uv);
			var uv2 = uvToScreen(calculatedUV);
			var isSky = 1 - ceil(depth);
			depth = mix(depth, 1, isSky);
			var temp = vec4(uv2, depth, 1) * cameraInverseViewProj;
			var originWS = temp.xyz / temp.w;
			return originWS;
		}

		function fragment() {
			var calculatedUV = input.uv;
			var origin = getPosition(calculatedUV);
			var height = origin.z;
			if( startHeight > height || endHeight < height ) discard;
			var opacityFactor = clamp((height - startHeight) / (endHeight - startHeight), 0, 1);
			var colorFactor = clamp((height - startColorHeight) / (endColorHeight - startColorHeight), 0, 1);
			var fogColor = mix(startColor, endColor, colorFactor);
			var fogOpacity = mix(startOpacity, endOpacity, opacityFactor);
			if( fogOpacity <= 0 ) discard;
			pixelColor = vec4(fogColor, fogOpacity);
		}
	};

	public function new() {
		super();
	}

}