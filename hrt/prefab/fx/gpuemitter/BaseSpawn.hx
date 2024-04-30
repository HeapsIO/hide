package hrt.prefab.fx.gpuemitter;

class BaseSpawn extends ComputeUtils {
	static var SRC = {
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4, 
			speed : Vec3,
			lifeTime : Float
		}, 33554432>;
		@const var SPEED_NORMAL : Bool;
		@param var minLifeTime : Float;
		@param var maxLifeTime : Float;
		@param var minStartSpeed : Float;
		@param var maxStartSpeed : Float;
		@param var absPos : Mat4;

		var lifeTime : Float;
		var modelView : Mat4;
		var relativeTransform : Mat4;
		var emitNormal : Vec3;
		function __init__() {
			emitNormal = vec3(0.0, 0.0, 1.0);
			lifeTime = mix(minLifeTime, maxLifeTime, (global.time + computeVar.globalInvocation.x * 0.5123789) % 1.0);
			relativeTransform = translationMatrix(vec3(0.0));
			modelView = relativeTransform * absPos;
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			if ( batchBuffer[idx].lifeTime < 1e-7 ) {
				batchBuffer[idx].modelView = modelView;
				var s = vec3(0.0, 0.0, 1.0);
				if ( SPEED_NORMAL )
					s = emitNormal;
				batchBuffer[idx].speed = s * maxStartSpeed;
				batchBuffer[idx].lifeTime = lifeTime;
			}
		}
	}
}