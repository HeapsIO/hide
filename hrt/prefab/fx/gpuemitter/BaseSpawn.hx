package hrt.prefab.fx.gpuemitter;

class BaseSpawn extends ComputeUtils {
	static var SRC = {
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4,
		}>;
		@param var particleBuffer : RWPartialBuffer<{
			speed : Vec3,
			life : Float,
			lifeTime : Float,
			random : Float,
			color : Float,
		}>;
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

		var life : Float;
		var particleRandom : Float;
		var modelView : Mat4;
		var relativeTransform : Mat4;
		var emitNormal : Vec3;
		var particleColor : Vec4;
		function __init__() {
			emitNormal = vec3(0.0, 0.0, 1.0);
			particleRandom = particleBuffer[computeVar.globalInvocation.x].random;
			life = mix(minLifeTime, maxLifeTime, (global.time + particleRandom) % 1.0);
			relativeTransform = translationMatrix(vec3(0.0));
			modelView = relativeTransform * absPos;
			particleColor = vec4(1.0);
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			var curLife = particleBuffer[idx].life;
			var curLifeTime = particleBuffer[idx].lifeTime;
			if ( FORCED || (!INFINITE && curLife > curLifeTime ) ) {
				var c = atomicAdd(atomic, 0, 1);
				if ( FORCED || (!INFINITE && c < rate) ) {
					batchBuffer[idx].modelView = modelView;
					var s = vec3(0.0, 0.0, 1.0);
					if ( SPEED_NORMAL )
						s = emitNormal;
					particleBuffer[idx].speed = s * maxStartSpeed;
					particleBuffer[idx].life = 0.0;
					// Keep in memory duration of particle to normalize curve update.
					particleBuffer[idx].lifeTime = life;
					particleBuffer[idx].color = intBitsToFloat(rgba2int(particleColor));
				}
			}
		}
	}
}