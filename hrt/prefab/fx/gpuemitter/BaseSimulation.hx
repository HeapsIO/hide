package hrt.prefab.fx.gpuemitter;

class BaseSimulation extends ComputeUtils {
	static var SRC = {
		@param var batchBuffer : RWPartialBuffer<{
			modelView : Mat4, 
		}>;
		@param var particleBuffer : RWPartialBuffer<{
			speed : Vec3,
			lifeTime : Float,
			lifeRatio : Float,
			random : Float,
		}>;

		@const var INFINITE : Bool = false;
		@const var FACE_CAM : Bool = false;
		@const var CAMERA_BOUNDS : Bool = false;

		@param var dtParam : Float;
		@param var cameraUp : Vec3;
		@param var boundsPos : Vec3;
		@param var boundsSize : Vec3;

		var dt : Float;
		var speed : Vec3;
		var lifeTime : Float;
		var particleRandom : Float;
		var modelView : Mat4;
		var instanceID : Int;
		var prevModelView : Mat4;
		var prevSpeed : Vec3;
		function __init__() {
			dt = dtParam;
			speed = particleBuffer[computeVar.globalInvocation.x].speed;
			lifeTime = particleBuffer[computeVar.globalInvocation.x].lifeTime;
			prevModelView = batchBuffer[computeVar.globalInvocation.x].modelView;
			particleRandom = particleBuffer[computeVar.globalInvocation.x].random;
		}

		function main() {
			var prevPos = vec3(0.0) * prevModelView.mat3x4();
			var align : Mat4;
			if ( FACE_CAM ) {
				align = alignMatrix(vec3(1.0, 0.0, 0.0), normalize(camera.position - prevPos));
				align = align * alignMatrix(vec3(0.0, 0.0, 1.0) * align.mat3(), cameraUp);
			} else
				align = rotateMatrixZ(computeVar.globalInvocation.x * 0.35487) * alignMatrix(vec3(0.0, 0.0, 1.0), normalize(speed));
			var newPos = prevPos + speed * dt;
			if ( CAMERA_BOUNDS )
				newPos = ((newPos - boundsPos) % boundsSize) + boundsPos;
			modelView = align * translationMatrix(newPos);
			var idx = computeVar.globalInvocation.x;
			if ( !INFINITE )
				particleBuffer[idx].lifeTime = lifeTime - dt;
			particleBuffer[idx].speed = speed;
			batchBuffer[idx].modelView = modelView;
		}
	}
}