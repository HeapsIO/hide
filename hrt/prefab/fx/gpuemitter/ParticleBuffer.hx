package hrt.prefab.fx.gpuemitter;

class ParticleBuffer extends hxsl.Shader {
	static var SRC = {
		@param var particleBuffer : RWBuffer<Float>;
		@param var particleStride : Int;

		function getParticleIndex( i : Int ) : Int {
			return i * particleStride;
		}

		function getParticleSpeed( i : Int ) : Vec3 {
			var p = getParticleIndex(i);
			return vec3(particleBuffer[p], particleBuffer[p + 1], particleBuffer[p + 2]);
		}

		function setParticleSpeed( i : Int, v : Vec3 ) {
			var p = getParticleIndex(i);
			particleBuffer[p] = v.x;
			particleBuffer[p + 1] = v.y;
			particleBuffer[p + 2] = v.z;
		}

		function getParticleLife( i : Int ) : Float {
			return particleBuffer[getParticleIndex(i) + 3];
		}

		function setParticleLife( i : Int, v : Float ) {
			particleBuffer[getParticleIndex(i) + 3] = v;
		}

		function getParticleLifeTime( i : Int ) : Float {
			return particleBuffer[getParticleIndex(i) + 4];
		}

		function setParticleLifeTime( i : Int, v : Float ) {
			particleBuffer[getParticleIndex(i) + 4] = v;
		}

		function getParticleRandom( i : Int ) : Float {
			return particleBuffer[getParticleIndex(i) + 5];
		}

		function getParticleColor( i : Int ) : Float {
			return particleBuffer[getParticleIndex(i) + 6];
		}

		function setParticleColor( i : Int, v : Float ) {
			particleBuffer[getParticleIndex(i) + 6] = v;
		}
	}
}
