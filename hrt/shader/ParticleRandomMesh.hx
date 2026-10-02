package hrt.shader;

enum ParticleRandomMeshAxis {
	PosX;
	NegX;
	PosY;
	NegY;
	PosZ;
	NegZ;
}

class ParticleRandomMesh extends hxsl.Shader {

	static var SRC = {
		@:import hrt.shader.BaseEmitter;

		// Direction along which the cells are laid out
		@const @param var axis : ParticleRandomMeshAxis = PosX;
		@range(1, 32) @param var cellCount : Int = 4;
		@range(0, 10) @param var cellSize : Float = 1.0;

		function vertex() {
			var s = (axis == NegX || axis == NegY || axis == NegZ) ? -1.0 : 1.0;
			var dir = axis.toInt() < PosY.toInt() ? vec3(s, 0.0, 0.0) : (axis.toInt() < PosZ.toInt() ? vec3(0.0, s, 0.0) : vec3(0.0, 0.0, s));
			var count = max(float(cellCount), 1.0);
			var cell = min(floor(particleRandom * count), count - 1.0);

			var pos = relativePosition * meshToModel.mat3x4();
			var local = dot(pos, dir) - cell * cellSize;
			if (abs(local) > cellSize * 0.5)
				pos = vec3(0.0);
			else
				pos -= dir * (cell * cellSize);
			relativePosition = pos * modelToMesh.mat3x4();
		}
	};
}
