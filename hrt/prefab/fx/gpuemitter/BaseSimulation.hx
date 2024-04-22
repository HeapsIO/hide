package hrt.prefab.fx.gpuemitter;

class BaseSimulation extends ComputeUtils {
	static var SRC = {
		@const(4096) var MAX_INSTANCE_COUNT : Int;
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4, 
			speed : Vec3,
			lifeTime : Float
		}, MAX_INSTANCE_COUNT>;

		@const var INFINITE : Bool = false;
		@const var FACE_CAM : Bool = false;

		@param var dtParam : Float;
		@param var cameraUp : Vec3;

		var dt : Float;
		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		var instanceID : Int;
		var prevModelView : Mat4;
		var prevSpeed : Vec3;
		function __init__() {
			dt = dtParam;
			speed = batchBuffer[computeVar.globalInvocation.x].speed;
			lifeTime = batchBuffer[computeVar.globalInvocation.x].lifeTime;
			prevModelView = batchBuffer[computeVar.globalInvocation.x].modelView;
		}

		function main() {
			{
				var prevPos = vec3(0.0) * prevModelView.mat3x4();
				var align : Mat4;
				if ( FACE_CAM ) {
					align = alignMatrix(vec3(1.0, 0.0, 0.0), normalize(camera.position - prevPos));
					align = align * alignMatrix(vec3(0.0, 0.0, 1.0) * align.mat3(), cameraUp);
				} else {
					align = rotateMatrixZ(computeVar.globalInvocation.x * 0.35487) * alignMatrix(vec3(0.0, 0.0, 1.0), normalize(speed));
				}
				modelView = align * translationMatrix(prevPos) * translationMatrix(speed * dt);
			}
			var idx = computeVar.globalInvocation.x;
			if ( !INFINITE )
				batchBuffer[idx].lifeTime = lifeTime - dt;
			batchBuffer[idx].speed = speed;
			batchBuffer[idx].modelView = modelView;
		}
	}
}