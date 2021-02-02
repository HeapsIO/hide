package hrt.shader;

class SpecularColorAlbedo extends hxsl.Shader {
	static var SRC = {
		var albedoGamma : Vec3;
		var customSpecularColor : Vec3;
		function fragment() {
			customSpecularColor = albedoGamma;
		}
	}
}

class SpecularColorFlat extends hxsl.Shader {
	static var SRC = {
		@param var specularColorValue : Vec3;
		var customSpecularColor : Vec3;
		function fragment() {
			customSpecularColor = specularColorValue;
		}
	}
}

class SpecularColorTexture extends hxsl.Shader {
	static var SRC = {
		@param var specularColorTexture : Sampler2D;
		var customSpecularColor : Vec3;
		var calculatedUV : Vec2;
		function fragment() {
			customSpecularColor = specularColorTexture.get(calculatedUV % 1.0).rgb;
		}
	}
}

class SpecularColor extends hxsl.Shader {
	static var SRC = {

		@param var specular : Float;
		@param var specularTint : Float;
		var customSpecularColor : Vec3;
		var pbrSpecularColor : Vec3;
		
		function fragment() {
			pbrSpecularColor = mix(vec3(1.0), customSpecularColor, specularTint) * vec3(specular * 0.08);
		}

	}
}
