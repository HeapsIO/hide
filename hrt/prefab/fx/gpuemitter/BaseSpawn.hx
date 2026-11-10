package hrt.prefab.fx.gpuemitter;

class BaseSpawn extends ComputeUtils {
	static var SRC = {
		@param var batchBuffer : RWBuffer<Vec4>;
		@param var batchStride : Int;
		@param var modelViewPos : Int;
		@param var particleBuffer : RWBuffer<Float>;
		@param var particleStride : Int;
		@param var atomic : RWBuffer<Int>;

		@const var FORCED : Bool = false;
		@const var INFINITE : Bool = false;
		@const var SPEED_NORMAL : Bool;
		@param var minLifeTime : Float;
		@param var maxLifeTime : Float;
		@param var minStartSpeed : Float;
		@param var maxStartSpeed : Float;
		@param var rate : Int;
		@param var absPos : Mat4;

		@:import h3d.shader.ColorSpaces;
		@:import hrt.prefab.fx.gpuemitter.ParticleBuffer;
		@:import h3d.shader.BufferUtils;

		var life : Float;
		var particleRandom : Float;
		var modelView : Mat4;
		var relativeTransform : Mat4;
		var emitNormal : Vec3;
		var particleColor : Vec4;
		function __init__() {
			setLayout(64,1,1);
			emitNormal = vec3(0.0, 0.0, 1.0);
			particleRandom = getParticleRandom(computeVar.globalInvocation.x);
			life = mix(minLifeTime, maxLifeTime, (global.time + particleRandom) % 1.0);
			relativeTransform = translationMatrix(vec3(0.0));
			modelView = absPos * relativeTransform;
			particleColor = vec4(1.0);
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			var curLife = getParticleLife(idx);
			var curLifeTime = getParticleLifeTime(idx);
			if ( FORCED || (!INFINITE && curLife > curLifeTime ) ) {
				var c = atomicAdd(atomic, 0, 1);
				if ( FORCED || (!INFINITE && c < rate) ) {
					writeMat4(batchBuffer, idx * batchStride + modelViewPos, modelView);
					var s = vec3(0.0, 0.0, 1.0);
					if ( SPEED_NORMAL )
						s = emitNormal;
					setParticleSpeed(idx, s * maxStartSpeed);
					setParticleLife(idx, 0.0);
					// Keep in memory duration of particle to normalize curve update.
					setParticleLifeTime(idx, life);
					setParticleColor(idx, intBitsToFloat(packIntColor(particleColor)));
				}
			}
		}
	}
}