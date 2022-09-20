package hrt.shader;

class ParticleColorLife extends hxsl.Shader {

	static var SRC = {
        @:import hrt.shader.BaseEmitter;

        @param var gradient : Sampler2D;
        
		var pixelColor : Vec4;

        function fragment() {
            pixelColor.rgb *= gradient.get(vec2(particleLife/particleLifeTime, 0.5)).rgb;
        }
	};
}