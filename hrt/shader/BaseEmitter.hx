package hrt.shader;

class BaseEmitter extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@perInstance @param var lifeTime : Float;
		@perInstance @param var life : Float;
		@perInstance @param var random : Float;

		@param var emitPosition : Vec3;

		@param var meshTransform : Mat4;
		@param var meshTransformInverse : Mat4;

		// Each particle as a random value asigned on spawn
		var particleRandom : Float;
		var particleLifeTime : Float;
		var particleLife : Float;
		var emitterPosition : Vec3;
		var meshToModel : Mat4;
		var modelToMesh : Mat4;

		function __init__() {
			particleRandom = random;
			particleLifeTime = lifeTime;
			particleLife = life;
			emitterPosition = emitPosition;
			meshToModel = meshTransform;
			modelToMesh = meshTransformInverse;
		}
	};

}