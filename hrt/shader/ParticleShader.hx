package hrt.shader;

/**
	The particle features of an emitter, added once to its batch when one of them is set. Each color multiplies the pixel color, alpha included:
	- the random color, one per particle, between two colors or in a gradient;
	- the fade color, over the life of the particle, from a color to another or along a gradient.
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

		// the texel of the gradient texture made for `t` (`hrt.impl.Gradient.textureFromData`)
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
		}
	};
}
