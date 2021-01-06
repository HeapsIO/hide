package hrt.shader;

class SpecularColor extends hxsl.Shader {
	static var SRC = {

		@param var specular : Float;
		@param var specularTint : Float;

		var pbrSpecularColor : Vec3;
		var albedo : Vec3;
		
		function fragment() {
			pbrSpecularColor = mix(vec3(1.0), albedo, specularTint) * vec3(specular * 0.08);
		}

	}
}
