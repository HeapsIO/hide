package hrt.shader;

class BaseEmitter extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@perInstance @param var lifeTime : Float;
		@perInstance @param var life : Float;
		@perInstance @param var random : Float;

		@param var emitPosition : Vec3;

		@param var meshTransform : Mat4;
		@param var meshTransformInverse : Mat4;

		// Particle colors, all disabled by default
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

		// Each particle as a random value asigned on spawn
		var particleRandom : Float;
		var particleLifeTime : Float;
		var particleLife : Float;
		var emitterPosition : Vec3;
		var meshToModel : Mat4;
		var modelToMesh : Mat4;

		function __init__() {
			particleRandom = random;
			particleLifeTime = lifeTime;
			particleLife = life;
			emitterPosition = emitPosition;
			meshToModel = meshTransform;
			modelToMesh = meshTransformInverse;
		}

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
				var a = 1.0;
				if( fadeIn > 0. ) a = min(a, t / fadeIn);
				if( fadeOut > 0. ) a = min(a, (1.0 - t) / fadeOut);
				pixelColor.a *= saturate(a);
			}
		}
	};

}
