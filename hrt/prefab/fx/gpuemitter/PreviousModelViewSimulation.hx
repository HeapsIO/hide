package hrt.prefab.fx.gpuemitter;

class PreviousModelViewSimulation extends hxsl.Shader {
	static var SRC = {
		@param var batchBuffer : RWBuffer<Vec4>;
		@param var batchStride : Int;
		@param var previousModelViewPos : Int;

		@:import h3d.shader.BufferUtils;

		var prevModelView : Mat4;
		function main() {
			writeMat4(batchBuffer, computeVar.globalInvocation.x * batchStride + previousModelViewPos, prevModelView);
		}
	}
}