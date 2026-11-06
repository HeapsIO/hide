package hrt.prefab.fx.gpuemitter;

class BaseSimulation extends ComputeUtils {
	static var SRC = {
		@param var batchBuffer : RWBuffer<Vec4>;
		@param var batchStride : Int;
		@param var modelViewPos : Int;
		@param var particleBuffer : RWBuffer<Float>;
		@param var particleStride : Int;

		@:import h3d.shader.ColorSpaces;
		@:import hrt.prefab.fx.gpuemitter.ParticleBuffer;
		@:import h3d.shader.BufferUtils;

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
		var preventCameraWrap : Bool;
		var absoluteTranslation : Mat4;
		var prevPos : Vec3;
		var nextPos : Vec3;

		function __init__() {
			setLayout(64, 1, 1);
			absoluteTranslation = translationMatrix(vec3(0.0));
			preventCameraWrap = false;
			dt = dtParam;
			speed = getParticleSpeed(computeVar.globalInvocation.x);
			life = getParticleLife(computeVar.globalInvocation.x);
			lifeTime = getParticleLifeTime(computeVar.globalInvocation.x);
			prevModelView = readMat4(batchBuffer, computeVar.globalInvocation.x * batchStride + modelViewPos);
			particleRandom = getParticleRandom(computeVar.globalInvocation.x);
			particleColor = unpackIntColor(floatBitsToInt(getParticleColor(computeVar.globalInvocation.x)));
			relativeTransform = scaleMatrix(((INFINITE || life < lifeTime) ? 1.0 : 0.0) * (computeVar.globalInvocation.x > curCount ? 0.0 : 1.0) * vec3(particleRandom * (maxSize - minSize) + minSize));
			prevPos = vec3(0.0) * prevModelView.mat3x4();
			nextPos = prevPos + speed * dt;
		}

		function main() {
			var align : Mat4;
			if ( FACE_CAM ) {
				align = lookAtMatrix(vec3(0.0), camera.position - prevPos, cameraUp);
			} else {
				align = rotateMatrixZ(computeVar.globalInvocation.x * 0.35487) * alignMatrix(vec3(0.0, 0.0, 1.0), normalize(speed));
			}
			
			modelView = relativeTransform * align * translationMatrix(nextPos) * absoluteTranslation;
			var idx = computeVar.globalInvocation.x;
			setParticleLife(idx, life + dt);
			setParticleSpeed(idx, speed);
			setParticleColor(idx, intBitsToFloat(packIntColor(particleColor)));
			writeMat4(batchBuffer, idx * batchStride + modelViewPos, modelView);
		}
	}
}