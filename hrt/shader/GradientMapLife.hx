package hrt.shader;

class GradientMapLife extends hxsl.Shader {

	static var SRC = {
        @:import hrt.shader.BaseEmitter;
		@const var sourceAlpha : Bool;
		@const var destAlpha : Bool = true;


        @param var gradient : Sampler2D;

        function fragment() {
			var t = sourceAlpha ? pixelColor.a : dot(pixelColor.rgb*pixelColor.rgb, vec3(0.2126, 0.7152, 0.0722));

			// force texture reapeat
			var s = gradient.size();
			var sample = gradient.get(vec2(saturate(t), saturate(particleLife/particleLifeTime)) * (s-vec2(1.0))/(s));
            pixelColor.rgb = sample.rgb;
			if (destAlpha)
				pixelColor.a = sample.a;
        }
	};
}