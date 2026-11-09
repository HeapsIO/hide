package hrt.shader;

/**
	Base shader for Particles, following the general direction of reducing the size of the shader list
**/
class ParticleShader extends hxsl.Shader {

	static var SRC = {
		@:import hrt.shader.BaseEmitter;

		@const var randomMode : hrt.prefab.fx.Emitter.RandomColorMode;
		@param var randomColor1 : Vec4;
		@param var randomColor2 : Vec4;
		@param var randomGradient : Sampler2D;

		@const var fadeMode : hrt.prefab.fx.Emitter.RandomColorMode;
		@param var fadeColor1 : Vec4;
		@param var fadeColor2 : Vec4;
		@param var fadeGradient : Sampler2D;

		@const var alphaFade : Bool;
		@param var fadeIn : Float;
		@param var fadeOut : Float;

		function gradientUV( t : Float, width : Float ) : Vec2 {
			return vec2((t * (width - 1.0) + 0.5) / width, 0.5);
		}

		function fragment() {
			if( randomMode == Colors )
				pixelColor *= mix(randomColor1, randomColor2, particleRandom);
			else if( randomMode == Gradient )
				pixelColor *= randomGradient.get(gradientUV(particleRandom, randomGradient.size().x));

			var t = saturate(particleLife / particleLifeTime);
			if( fadeMode == Colors )
				pixelColor *= mix(fadeColor1, fadeColor2, t);
			else if( fadeMode == Gradient )
				pixelColor *= fadeGradient.get(gradientUV(t, fadeGradient.size().x));

			if( alphaFade ) {
				if( fadeIn > 0. ) pixelColor.a *= smoothstep(0., fadeIn, t);
				if( fadeOut > 0. ) pixelColor.a *= smoothstep(0., fadeOut, 1.0 - t);
			}
		}
	};
}
