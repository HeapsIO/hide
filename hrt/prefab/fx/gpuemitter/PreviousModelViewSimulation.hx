package hrt.prefab.fx.gpuemitter;

class PreviousModelViewSimulation extends hxsl.Shader {
	static var SRC = {
		@param var batchBuffer : RWPartialBuffer<{
			previousModelView : Mat4
		}>;

		var prevModelView : Mat4;
		function main() {
			var idx = computeVar.globalInvocation.x;
			batchBuffer[idx].previousModelView = prevModelView;
		}
	}
}