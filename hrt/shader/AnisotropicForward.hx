package hrt.shader;

class FrequencyValue extends hxsl.Shader {
	static var SRC = {

		@param var intensity : Float;
		@param var noiseIntensity : Float;
		@param var noiseFrequency : Float;

		@param var dirVector : Vec3;

		var calculatedUV : Vec2;
		var anisotropy : Float;
		var direction : Vec3;

		function fragment()  {
			anisotropy = intensity;
			var theta = dot(dirVector.xy, calculatedUV.xy) * noiseFrequency;
			var ctheta = cos(theta);
			var stheta = sin(theta);
			var noiseDir = vec3(dirVector.x * ctheta - dirVector.y * stheta, dirVector.x * stheta + dirVector.y * ctheta, 0.0);
			direction = mix(dirVector, noiseDir, noiseIntensity);

		}
	}
}

class FlatValue extends hxsl.Shader {
	static var SRC = {

		@param var intensity : Float;
		@param var dirVector : Vec3;

		var anisotropy : Float;
		var direction : Vec3;

		function fragment()  {
			anisotropy = intensity;
			direction = dirVector;
		}
	}
}

class NoiseTexture extends hxsl.Shader {
	static var SRC = {

		@param var intensityFactor : Float;
		@param var rotationOffset : Float;
		@param var noiseIntensityTexture : Sampler2D;
		@param var noiseDirectionTexture : Sampler2D;
		var anisotropy : Float;
		var direction : Vec3;
		var calculatedUV : Vec2;

		function fragment()  {
			anisotropy = noiseIntensityTexture.get(calculatedUV % 1.0).r * intensityFactor;
			var angle = noiseDirectionTexture.get(calculatedUV % 1.0).r * 2 * PI + rotationOffset;
			direction = vec3(cos(angle), sin(angle), 0.0);
		}
	}
}

class AnisotropicForward extends h3d.shader.pbr.DefaultForward {
	static var SRC = {

		@global var global : {
            @perObject var modelView : Mat4;
		};

		var anisotropy : Float;
		var direction : Vec3;

		var tangentWorld : Vec3;
		var bitangentWorld : Vec3;

		function getAnisotropicRoughness( roughness : Float, anisotropy : Float ) : Vec2 {
			// [Burley12] Offers more pleasant and intuitive results, but is slightly more expensive
			//var da = sqrt(1 - 0.9 * anisotropy);
			//var at = anisotropy / da;
			//var ab = anisotropy * da;

			// [Kulla17] Allows creation of sharp highlights
			var at = max(roughness * (1.0 + anisotropy), 0.001);
			var ab = max(roughness * (1.0 - anisotropy), 0.001);

			return vec2(at, ab);
		}

		function sqr( f : Float ) : Float { return f * f; }
		function cos_theta( w : Vec3 ) : Float { return w.z; }
		function cos_2_theta( w : Vec3 ) : Float { return w.z * w.z; }
		function sin_2_theta( w : Vec3 ) : Float { return max(0., 1. -cos_2_theta(w)); }
		function sin_theta( w : Vec3 ) : Float { return sqrt(sin_2_theta(w)); }
		function tan_theta( w : Vec3 ) : Float { return sin_theta(w) / cos_theta(w); }
		function cos_phi( w : Vec3 ) : Float { return (sin_theta(w) == 0.) ? 1. : clamp(w.x / sin_theta(w), -1., 1.); }
		function sin_phi( w : Vec3 ) : Float { return (sin_theta(w) == 0.) ? 0. : clamp(w.y / sin_theta(w), -1., 1.); }

		function normalDistributionGGXAnisotropic( omega_h : Vec3, alpha_x : Float, alpha_y : Float ) : Float {
			var slope_x = -(omega_h.x / omega_h.z);
			var slope_y = -(omega_h.y / omega_h.z);
			var denom = (1. + (sqr(slope_x) / sqr(alpha_x)) + (sqr(slope_y) / sqr(alpha_y)) );
			return 1. / ( ( PI * alpha_x * alpha_y) * (sqr(denom)) ) / sqr(sqr(cos_theta(omega_h)));
		}

		function lambdaGGXAnisotropic( omega : Vec3, alpha_x : Float, alpha_y: Float) : Float {
			var cos_phi = cos_phi(omega);
			var sin_phi = sin_phi(omega);
			var alpha_o = sqrt(sqr(cos_phi) * sqr(alpha_x) + sqr(sin_phi) * sqr(alpha_y));
			var a = 1. / (alpha_o * tan_theta(omega));
			return( 0.5 * (-1. + sqrt(1. + 1. / (a*a))) );
		}

		function fresnelSchlick( wo_dot_wh : Float, F0 : Vec3 ) : Vec3 {
			return F0 + (1. - F0) * pow(1. - wo_dot_wh, 5.);
		}

		function directLighting( lightColor : Vec3, lightDirection : Vec3) : Vec3 {

			var NdL = clamp(transformedNormal.dot(lightDirection), 0.0, 1.0);
			var result = vec3(0,0,0);

			if( lightColor.dot(lightColor) > 0.0001 && NdL > 0.0 ) {

				var ar = getAnisotropicRoughness(roughness, anisotropy);
				var at = ar.x;
				var ab = ar.y;

				// PBRT - Computations are done in tangent space
				var TBN_t = mat3(tangentWorld, bitangentWorld, transformedNormal);
				var wo = normalize(view * TBN_t);
				var wi = normalize(lightDirection * TBN_t);
				var wg = vec3(0,0,1); // normalize(transformedNormal * TBN_t);
				var wh = normalize(wo + wi);
				var wi_dot_wh = clamp(dot(wi, wh),0.,1.); 		// saturate(dot(L,H))
				var wg_dot_wi = clamp(cos_theta(wi),0.,1.); 	// saturate(dot(N,L))

				var alpha_x = at * at;
        		var alpha_y = ab * ab;
				var D = normalDistributionGGXAnisotropic(wh, alpha_x, alpha_y);
				var F = fresnelSchlick(wi_dot_wh, F0);
				var lambda_wo = lambdaGGXAnisotropic(wo, alpha_x, alpha_y);
				var lambda_wi = lambdaGGXAnisotropic(wi, alpha_x, alpha_y);
				var G = 1. / (1. + lambda_wo + lambda_wi);

				var specular = (D * F * G) / ( 4. * cos_theta(wi) * cos_theta(wo) ) ;
				var diffuse = albedoGamma / PI * (1.0 - metalness);

				result = (diffuse + specular) * lightColor * wg_dot_wi;
			}

			return result;
		}

		function indirectLighting() : Vec3 {

			var anisotropicDirection = anisotropy >= 0.0 ? bitangentWorld : tangentWorld;
			var anisotropicTangent = cross(anisotropicDirection, view);
			var anisotropicNormal = cross(anisotropicTangent, anisotropicDirection);
			var bentNormal = normalize(mix(transformedNormal, anisotropicNormal, anisotropy));
			var rotatedNormal = rotateNormal(bentNormal);
			var reflectVec = reflect(-view, bentNormal);
			var rotatedReflecVec = rotateNormal(reflectVec);

			var F = F0 + (max(vec3(1 - roughness), F0) - F0) * exp2( ( -5.55473 * NdV - 6.98316) * NdV );
			var diffuse = irrDiffuse.get(rotatedNormal).rgb * albedoGamma;
			var envSpec = textureLod(irrSpecular, rotatedReflecVec, roughness * irrSpecularLevels).rgb;
			var envBRDF = irrLut.get(vec2(roughness, NdV));
			var specular = envSpec * (F * envBRDF.x + envBRDF.y);
			var indirect = (diffuse * (1 - metalness) * (1 - F) + specular) * irrPower;

			return indirect * occlusion;
		}

		function init() {
			view = (cameraPosition - transformedPosition).normalize();
			NdV = transformedNormal.dot(view).max(0.);
			var tmp = cross(direction * global.modelView.mat3(), transformedNormal).normalize();
			bitangentWorld = cross(tmp, transformedNormal).normalize();
			tangentWorld = cross(bitangentWorld, transformedNormal).normalize();
		}
	}
}