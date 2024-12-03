package hrt.prefab.fx.gpuemitter;

class UpdateParamShader extends hxsl.Shader {
	static var SRC = {

		@param var batchBuffer : RWBuffer<Float>;

		@param var particleBuffer : RWPartialBuffer<{ life : Float, lifeTime : Float }>;

		@param var paramTexture : Sampler2D;
		@param var stride : Int;
		@param var pos : Int;

		@param var row : Float;

		function main() {
			var idx = computeVar.globalInvocation.x;
			batchBuffer[idx * stride + pos] = paramTexture.get(vec2(1.0 - particleBuffer[idx].life / particleBuffer[idx].lifeTime, row)).x;
		}
	}
}