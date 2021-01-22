package hrt.shader;

class ParticleForward extends h3d.shader.pbr.DefaultForward implements h3d.scene.MeshBatch.MeshBatchAccess {

	public var perInstance : Bool = false;

	static var SRC = {

		@const var VERTEX : Bool = true;
		@param var directLightingIntensity : Float;
		@param var indirectLightingIntensity : Float;
		var backLightingIntensity : Float;
		var lighting : Vec3;

		function indirectLighting() : Vec3 {
			var rotatedNormal = rotateNormal(transformedNormal);
			var diffuse = irrDiffuse.get(rotatedNormal).rgb;
			var indirect = diffuse * irrPower * indirectLightingIntensity;
			return indirect;
		}
		
		function directLighting( lightColor : Vec3, lightDirection : Vec3) : Vec3 {
			var result = vec3(0);

			var NdL = transformedNormal.dot(lightDirection);
			result += lightColor * clamp(NdL, 0.0, 1.0);

			var bNdL = clamp(-NdL, 0.0, 1.0);
			result += (lightColor * bNdL) * backLightingIntensity;

			return result * directLightingIntensity;
		}

		function evaluateLighting() : Vec3 {
			var lightAccumulation = vec3(0);

			// Dir Light
			for( l in 0 ... dirLightCount )
				lightAccumulation += evaluateDirLight(l);
			// Point Light
			for( l in 0 ... pointLightCount )
				lightAccumulation += evaluatePointLight(l);
			// Spot Light
			for( l in 0 ... spotLightCount )
				lightAccumulation += evaluateSpotLight(l);

			// Indirect only support the main env from the scene at the moment
			if( USE_INDIRECT > 0.0)
				lightAccumulation += indirectLighting();

			return lightAccumulation;
		}

		function init() {
			view = (cameraPosition - transformedPosition).normalize();
			NdV = transformedNormal.dot(view).max(0.);
		}

		function vertex() {
			if( VERTEX ) {
				init();
				lighting = evaluateLighting();
			}
		}

		function fragment() {
			if( !VERTEX ) {
				init();
				lighting = evaluateLighting();
			}
			output.color.rgb *= lighting / PI;
		}

	}
}