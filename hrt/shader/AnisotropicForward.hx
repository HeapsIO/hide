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

		//-----------------------------------------------------------------------------
		//-- Uniforms -----------------------------------------------------------------

		@global var global : {
            @perObject var modelView : Mat4;
		};

		//-----------------------------------------------------------------------------
		//-- Attributes ---------------------------------------------------------------

		var anisotropy : Float;		/**< Controls the lobe direction */
		var direction : Vec3;		/**< ? */
		var tangentWorld : Vec3;	/**< World space   tangent vector */
		var bitangentWorld : Vec3;	/**< World space bitangent vector */


		//-----------------------------------------------------------------------------
		//-- Environment textures -----------------------------------------------------

		function getBRDFLUT( roughness : Float, NdV : Float ) : Vec2
		{
			return irrLut.get(vec2(roughness, NdV)).rg;
		}

		function getEnvDiffuse( direction : Vec3 ) : Vec3
		{
			return irrDiffuse.get( rotateNormal(direction) ).rgb;
		}

		function getEnvSpecular( direction : Vec3, roughness : Float ) : Vec3
		{
			return textureLod(irrSpecular, rotateNormal(direction), roughness * irrSpecularLevels).rgb;
		}

		//-----------------------------------------------------------------------------
		//-- Mappings -----------------------------------------------------------------

		/**
		 * \brief Returns Anisotropy Roughness mapping
		 * (Taking into account perceptual roughness mapping)
		 *
		 * From Kulla & Conty in 2017
		 * "Revisiting Physically Based Shading at Imageworks"
		 */
		function getAnisotropicRoughness( roughness : Float, anisotropy : Float ) : Vec2
		{
			var at = max(roughness*roughness*(1.0 + anisotropy), 0.001);
			var ab = max(roughness*roughness*(1.0 - anisotropy), 0.001);
			return vec2(at, ab);
		}


		//-----------------------------------------------------------------------------
		//-- BRDF - Fresnel -----------------------------------------------------------

		/** \brief Schlick's Fresnel approximation */
		function fresnelSchlick( VdH : Float, F0 : Vec3 ) : Vec3
		{
			return F0 + (1. - F0) * pow(1. - VdH, 5.);
		}

		/**
		 * \brief Roughness dependent Fresnel term (Used for indirect lighting)
		 * Prevents high specular color at edge for rough surfaces
		 */
		function fresnelSchlickWithRoughness( NdV : Float, F0 : Vec3, alpha : Float ) : Vec3
		{
			var Fr = max( vec3(1.0-alpha), F0 ) - F0;
			return F0 + Fr * pow(1. - NdV, 5.);
		}

		//-----------------------------------------------------------------------------
		//-- BRDF - GGX Microfacet Distribution ---------------------------------------

		/** \brief GGX Anisotropic Normal Distribution Function */
		function GGX_Aniso_NDF(	alpha_t : Float,
								alpha_b : Float,
								ToH 	: Float,
								BoH 	: Float,
								NoH 	: Float) : Float
		{
			var invpi = 1.0/PI;
			var v = vec3(alpha_b*ToH,alpha_t*BoH, alpha_t*alpha_b*NoH);
			var v2 = dot(v,v);
			var a2 = alpha_t*alpha_b;
			var w2 = a2/v2;
			return( a2*w2*w2*invpi );
		}

		/** \brief GGX Anisotropic Visibility term : corresponds to G / ( 4 * NoV * NoL ) */
		function GGX_Aniso_Visibility(	alpha_t : Float, alpha_b : Float,
										ToV 	: Float, BoV 	 : Float, NoV : Float,
										ToL 	: Float, BoL 	 : Float, NoL : Float) : Float
		{
			var lambdaV = NoL * length(vec3(alpha_t * ToV, alpha_b * BoV, NoV));
			var lambdaL = NoV * length(vec3(alpha_t * ToL, alpha_b * BoL, NoL));
			var v = 0.5 / (lambdaV + lambdaL);
			return clamp(v,0.0,1.0);
		}

		//-----------------------------------------------------------------------------
		//-- Overrided Functions ------------------------------------------------------

		function directLighting( lightColor : Vec3, lightDirection : Vec3) : Vec3
		{
			var result = vec3(0,0,0);
			/* Checks if is lit */
			var NdL = clamp(transformedNormal.dot(lightDirection), 0.0, 1.0);
			if( lightColor.dot(lightColor) > 0.0001 && NdL > 0.0 )
			{
				/* Half Vector */
				var H = normalize(view+lightDirection);
				/* Normal dot products */
				var NdH = dot(transformedNormal,H);
				/* Tangent dot products */
				var TdH = dot(tangentWorld,H);
				var TdV = dot(tangentWorld,view);
				var TdL = dot(tangentWorld,lightDirection);
				/* Bitangent dot products */
				var BdH = dot(bitangentWorld,H);
				var BdV = dot(bitangentWorld,view);
				var BdL = dot(bitangentWorld,lightDirection);
				/* Anisotropic roughness mapping */
				var alphas_aniso = getAnisotropicRoughness(roughness, anisotropy);
				var alpha_t = alphas_aniso.x;
				var alpha_b = alphas_aniso.y;
				/* Fresnel */
				var VdH = dot(view,H);
				var F = fresnelSchlick( max(VdH,0.0) , F0 );
				/* Specular Term */
				var D = GGX_Aniso_NDF(
					alpha_t, alpha_b,
					TdH, BdH, NdH
				);
				var Vis = GGX_Aniso_Visibility(
					alpha_t, alpha_b,
					TdV, BdV, NdV,
					TdL, BdL, NdL
				);
				var specular_term = D * F * Vis;
				/* Diffuse Term */
				var diffuse_term = albedoGamma / PI;
				var diffuse_factor = (1.0 - metalness) * (1.0 - F);
				/* Direct Lighting : Final  */
				result = NdL * lightColor * (diffuse_factor*diffuse_term + specular_term);
			}
			return(result);
		}

		function indirectLighting() : Vec3
		{
			/* Perceptual Roughness mapping (alpha = roughness^2) */
			var alpha = roughness*roughness;
			/* Bent Normal Indirect Lighting Hack */
			var anisotropicDirection = anisotropy >= 0.0 ? bitangentWorld : tangentWorld;
			var anisotropicTangent = cross(anisotropicDirection, view);
			var anisotropicNormal = cross(anisotropicTangent, anisotropicDirection);
			var bentNormal = normalize(mix(transformedNormal, anisotropicNormal, anisotropy));
			var reflectVec = reflect(-view, bentNormal);
			/* Prefiltered Importance Sampling */
			var envDiff = getEnvDiffuse(bentNormal);
			var envSpec = getEnvSpecular(reflectVec,alpha);
			var envBRDF = getBRDFLUT(alpha,NdV);
			var F = fresnelSchlickWithRoughness( max(NdV,0.0), F0, alpha );
			/* Combining Diffuse and Specular */
			var diffuse = envDiff * albedoGamma;
			var diffuse_factor = (1.0-metalness) * (1.0-F);
			var specular = envSpec * (F * envBRDF.x + envBRDF.y);
			var indirect = (diffuse_factor*diffuse + specular) * irrPower;
			/* Final */
			return max(vec3(0), indirect * occlusion);
		}

		function init()
		{
			view = (cameraPosition - transformedPosition).normalize();
			NdV = transformedNormal.dot(view).max(0.);
			var tmp = cross(direction * global.modelView.mat3(), transformedNormal).normalize();
			bitangentWorld = cross(tmp, transformedNormal).normalize();
			tangentWorld = cross(bitangentWorld, transformedNormal).normalize();
		}
	}
}