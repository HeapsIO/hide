package hrt.shader;

class ParticleForward extends h3d.shader.pbr.DefaultForward implements h3d.scene.MeshBatch.MeshBatchAccess {

	public var perInstance : Bool = false;

	static var SRC = {

		@global var global : {
			@perObject var modelView : Mat4;
		};

		@const var NORMAL : Bool = false;
		@const var NORMAL_FLIP_Y : Bool = false;
		@const var NORMAL_FLIP_X : Bool = false;
		@const var VERTEX : Bool = true;

		// Lighting Params
		@param var directLightingIntensity : Float;
		@param var indirectLightingIntensity : Float;

		// Normal Map Params
		@param var normalMap : Sampler2D;
		@param var normalIntensity : Float;
		var calculatedUV : Vec2;

		// CuvedNormal Input
		var localNormal : Vec3;
		var localTangent : Vec3;

		// BackLighting Input
		var backLightingIntensity : Float;

		// HL2 Basis
		@param var hl2_basis0 : Vec3;
		@param var hl2_basis1 : Vec3;
		@param var hl2_basis2 : Vec3;
		// HL2 Basis Transformed
		var hl2_basis0Transformed : Vec3;
		var hl2_basis1Transformed : Vec3;
		var hl2_basis2Transformed : Vec3;
		// HL2 Basis Light Accumulation
		var color0 : Vec3;
		var color1 : Vec3;
		var color2 : Vec3;
		// Light Accumulation
		var lighting : Vec3;

		function indirectLighting() : Vec3 {
			var indirect = vec3(0);

			// HL2 basis for vertexLighting with normalmap
			if( NORMAL && VERTEX ) {
				var rotatedNormal = rotateNormal(transformedNormal);
				var diffuse = irrDiffuse.get(rotatedNormal).rgb;
				color0 += diffuse * irrPower * indirectLightingIntensity;
				color1 += diffuse * irrPower * indirectLightingIntensity;
				color2 += diffuse * irrPower * indirectLightingIntensity;
			}
			else {
				var rotatedNormal = rotateNormal(transformedNormal);
				var diffuse = irrDiffuse.get(rotatedNormal).rgb;
				indirect += diffuse * irrPower * indirectLightingIntensity;
			}
			return indirect;
		}

		function directLighting( lightColor : Vec3, lightDirection : Vec3) : Vec3 {
			var result = vec3(0);

			// HL2 basis for vertexLighting with normalmap
			if( NORMAL && VERTEX ) {

				var localBitangent = normalize(localNormal.cross(vec3(localTangent.x, localTangent.y, localTangent.z)));
				var TBN = mat3(	vec3(localTangent.x, localBitangent.x, localNormal.x),
								vec3(localTangent.y, localBitangent.y, localNormal.y),
								vec3(localTangent.z, localBitangent.z, localNormal.z));
				
				hl2_basis0Transformed = normalize(hl2_basis0 * TBN * global.modelView.mat3());
				hl2_basis1Transformed = normalize(hl2_basis1 * TBN * global.modelView.mat3());
				hl2_basis2Transformed = normalize(hl2_basis2 * TBN * global.modelView.mat3());

				var weights = saturate(vec3(lightDirection.dot(hl2_basis0Transformed), 
											lightDirection.dot(hl2_basis1Transformed), 
											lightDirection.dot(hl2_basis2Transformed)));

				color0 += weights.x * lightColor * directLightingIntensity;
				color1 += weights.y * lightColor * directLightingIntensity;
				color2 += weights.z * lightColor * directLightingIntensity;
			}
			else {
				// Front Lighting
				var NdL = transformedNormal.dot(lightDirection);
				result += lightColor * clamp(NdL, 0.0, 1.0);
			}

			// Back Lighting
			var bNdL = clamp(-transformedNormal.dot(lightDirection), 0.0, 1.0);
			result += lightColor * bNdL * backLightingIntensity;

			return result * directLightingIntensity;
		}

		function evaluateLighting() : Vec3 {
			var lightAccumulation = vec3(0);

			color0 = vec3(0);
			color1 = vec3(0);
			color2 = vec3(0);

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
			if( USE_INDIRECT )
				lightAccumulation += indirectLighting();

			return lightAccumulation;
		}

		function normalMapping() {
			var n = unpackNormal(normalMap.get(calculatedUV).rgba);
			n = vec3(NORMAL_FLIP_X ? -n.x : n.x, NORMAL_FLIP_Y ? -n.y : n.y, n.z);
			var localBitangent = normalize(localNormal.cross(vec3(localTangent.x, localTangent.y, localTangent.z)));
			var TBN = mat3(	vec3(localTangent.x, localBitangent.x, localNormal.x),
							vec3(localTangent.y, localBitangent.y, localNormal.y),
							vec3(localTangent.z, localBitangent.z, localNormal.z));
			transformedNormal = mix(transformedNormal, normalize(n * TBN * global.modelView.mat3()), normalIntensity);
		}

		function init() {

			// Normal Mapping with pixel mode
			if( NORMAL && !VERTEX ) 
				normalMapping();
			
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
			if( VERTEX && NORMAL ) {
				// Normal Mapping with vertex mode
				normalMapping();
				var w = saturate(vec3(	transformedNormal.dot(hl2_basis0Transformed), 
										transformedNormal.dot(hl2_basis1Transformed), 
										transformedNormal.dot(hl2_basis2Transformed)));
				lighting += color0 * w.x + color1 * w.y + color2 * w.z;
			}
			else if( !VERTEX ) {
				init();
				lighting = evaluateLighting();
			}

			output.color.rgb *= lighting;
		}

	}
}