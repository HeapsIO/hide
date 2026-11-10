package hrt.prefab.fx.gpuemitter;

class UpdateParamShader extends hxsl.Shader {
	static var SRC = {

		@param var batchBuffer : RWBuffer<Float>;

		@param var particleBuffer : RWBuffer<Float>;
		@param var particleStride : Int;

		@:import hrt.prefab.fx.gpuemitter.ParticleBuffer;

		@param var paramTexture : Sampler2D;
		@param var stride : Int;
		@param var pos : Int;

		@param var row : Float;

		function main() {
			setLayout(64, 1, 1);
			var idx = computeVar.globalInvocation.x;
			batchBuffer[idx * stride + pos] = paramTexture.getLod(vec2(1.0 - getParticleLife(idx) / getParticleLifeTime(idx), row), 0.0).x;
		}
	}
}