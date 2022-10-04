package hrt.shader;

class ParticleFade extends hxsl.Shader {

	static var SRC = {
        @:import hrt.shader.BaseEmitter;

        @param var fadeInLife : Float = 0.1;
        @param var fadeOutLife : Float = 0.1;
        @param @range(0.01,10) var power : Float = 1.0;

		var pixelColor : Vec4;

        function fragment() {
            var t = particleLife / particleLifeTime;
            var fadeIn = t / max(0.0001, fadeInLife);
            var fadeOut = (1.0-t) / max(0.0001, fadeOutLife);

            pixelColor.a *= pow(min(min(fadeIn, fadeOut), 1.0), power);
        }
	};
}