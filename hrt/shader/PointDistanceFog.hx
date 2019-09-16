package hrt.shader;

class PointDistanceFog extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var startDistance : Float;
		@param var endDistance : Float;
		@param var startOpacity : Float;
		@param var endOpacity: Float;

		@param var startColorDistance : Float;
		@param var endColorDistance : Float;
		@param var startColor : Vec3;
		@param var endColor : Vec3;

		@param var startHeight : Float;
		@param var endHeight : Float;
		@param var startHeightOpacity : Float;
		@param var endHeightOpacity: Float;

		@param var pointPosition : Vec3;

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
			var distance = (origin - pointPosition).length();
			var heightDistance = abs(origin.z - pointPosition.z);
			if( startDistance > distance ) discard;
			var opacityFactor = clamp((distance - startDistance) / (endDistance - startDistance), 0, 1);
			var heightOpacityFactor = clamp((heightDistance - startHeight) / (endHeight - startHeight), 0, 1);
			var colorFactor = clamp((distance - startColorDistance) / (endColorDistance - startColorDistance), 0, 1);
			var fogColor = mix(startColor, endColor, colorFactor);
			var fogOpacity = mix(startOpacity, endOpacity, opacityFactor);
			var heightFogOpacity = mix(startHeightOpacity, endHeightOpacity, heightOpacityFactor);
			var opacity = min(fogOpacity, heightFogOpacity);
			if( opacity <= 0 ) discard;
			pixelColor = vec4(fogColor, opacity);
		}
	};

	public function new() {
		super();
	}

}