package hrt.shader;

class EmissiveMult extends hxsl.Shader {
	static var SRC = {
		@param var power : Float;

		var emissive : Float;

		function fragment() {
			emissive = emissive * power;
		}
	}
}