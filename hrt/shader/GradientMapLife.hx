package hrt.shader;

class GradientMapLife extends hxsl.Shader {

	static var SRC = {
		@:import hrt.shader.BaseEmitter;
		@const var sourceAlpha : Bool;
		@const var colorMult : Bool;
		@const var destAlpha : Bool = true;


		@param var gradient : Sampler2D;

		function fragment() {
			// force texture reapeat
			var s = gradient.size();
			var sample = gradient.get(vec2(saturate(particleLife/particleLifeTime)) * (s-vec2(1.0))/(s));
			if (colorMult) {
				pixelColor.rgb *= sample.rgb;
			}
			else {
				pixelColor.rgb = sample.rgb;
			}

			if (destAlpha) {
				pixelColor.a *= sample.a;
			}
		}
	};
}