package hrt.prefab.fx.gpuemitter;

class BaseSimulation extends ComputeUtils {
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

		@:import h3d.shader.ColorSpaces;

		@const var FACE_CAM : Bool = false;
		@const var CAMERA_BOUNDS : Bool = false;
		@const var INFINITE : Bool = false;

		@param var dtParam : Float;
		@param var cameraUp : Vec3;
		@param var boundsPos : Vec3;
		@param var boundsSize : Vec3;
		@param var minSize : Float;
		@param var maxSize : Float;
		@param var curCount : Int;

		var dt : Float;
		var speed : Vec3;
		var life : Float;
		var lifeTime : Float;
		var particleRandom : Float;
		var particleColor : Vec4;
		var modelView : Mat4;
		var prevModelView : Mat4;
		var prevSpeed : Vec3;
		var relativeTransform : Mat4;
		var computeCameraBounds : Bool;
		var absoluteTranslation : Mat4;

		function __init__() {
			absoluteTranslation = translationMatrix(vec3(0.0));
			computeCameraBounds = true;
			dt = dtParam;
			speed = particleBuffer[computeVar.globalInvocation.x].speed;
			life = particleBuffer[computeVar.globalInvocation.x].life;
			lifeTime = particleBuffer[computeVar.globalInvocation.x].lifeTime;
			prevModelView = batchBuffer[computeVar.globalInvocation.x].modelView;
			particleRandom = particleBuffer[computeVar.globalInvocation.x].random;
			particleColor = unpackIntColor(floatBitsToInt(particleBuffer[computeVar.globalInvocation.x].color));
			relativeTransform = scaleMatrix(((INFINITE || life < lifeTime) ? 1.0 : 0.0) * (computeVar.globalInvocation.x > curCount ? 0.0 : 1.0) * vec3(particleRandom * (maxSize - minSize) + minSize));
		}

		function main() {
			var prevPos = vec3(0.0) * prevModelView.mat3x4();
			var align : Mat4;
			if ( FACE_CAM ) {
				align = lookAtMatrix(vec3(0.0), camera.position - prevPos, cameraUp);
			} else
				align = rotateMatrixZ(computeVar.globalInvocation.x * 0.35487) * alignMatrix(vec3(0.0, 0.0, 1.0), normalize(speed));
			var newPos = prevPos + speed * dt;
			if ( CAMERA_BOUNDS && computeCameraBounds){
				newPos = ((newPos - boundsPos) % boundsSize) + boundsPos;
			}
			modelView = relativeTransform * align * translationMatrix(newPos) * absoluteTranslation;
			var idx = computeVar.globalInvocation.x;
			particleBuffer[idx].life = life + dt;
			particleBuffer[idx].speed = speed;
			particleBuffer[idx].color = intBitsToFloat(packIntColor(particleColor));
			batchBuffer[idx].modelView = modelView;
		}
	}
}