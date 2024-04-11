package hrt.prefab.fx.gpuemitter;

class BaseSimulation extends ComputeUtils {
	static var SRC = {
		@const(4096) var MAX_INSTANCE_COUNT : Int;
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4, 
			speed : Vec3,
			lifeTime : Float
		}, MAX_INSTANCE_COUNT>;

		@param var dtParam : Float;
		@const var INFINITE : Bool = false;

		var dt : Float;
		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		var instanceID : Int;
		function __init__() {
			speed = batchBuffer[computeVar.globalInvocation.x].speed;
			lifeTime = batchBuffer[computeVar.globalInvocation.x].lifeTime;
			modelView = batchBuffer[computeVar.globalInvocation.x].modelView;
			dt = dtParam;
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			if ( !INFINITE )
				batchBuffer[idx].lifeTime = lifeTime - dt;
			batchBuffer[idx].speed = speed;
			batchBuffer[idx].modelView = modelView;
		}
	}
}