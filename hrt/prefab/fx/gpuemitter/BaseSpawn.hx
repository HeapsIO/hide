package hrt.prefab.fx.gpuemitter;

class BaseSpawn extends ComputeUtils {
	static var SRC = {
		@const(4096) var MAX_INSTANCE_COUNT : Int;
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4, 
			speed : Vec3,
			lifeTime : Float
		}, MAX_INSTANCE_COUNT>;
		@param var minLifeTime : Float;
		@param var maxLifeTime : Float;

		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		function __init__() {
			speed = vec3(0.0);
			lifeTime = mix(minLifeTime, maxLifeTime, (global.time + computeVar.globalInvocation.x * 0.5123789) % 1.0);
			modelView = translationMatrix(vec3(computeVar.globalInvocation.x / MAX_INSTANCE_COUNT, 0.0, 0.0));
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			if ( batchBuffer[idx].lifeTime < 1e-7 ) {
				batchBuffer[idx].modelView = modelView;
				batchBuffer[idx].speed = speed;
				batchBuffer[idx].lifeTime = lifeTime;
			}
		}
	}
}