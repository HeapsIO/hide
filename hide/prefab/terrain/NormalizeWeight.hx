package hide.prefab.terrain;

class NormalizeWeight extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var weightTextures : Sampler2DArray;
		@param var weightCount : Int;
		@param var baseTexIndex : Int;
		@param var curTexIndex : Int;

		function fragment() {
			var refValue = weightTextures.get(vec3(calculatedUV, baseTexIndex)).r;
			var sum = 0.0;
			for(i in 0 ... weightCount)
				if(i != baseTexIndex) sum += weightTextures.get(vec3(calculatedUV, i)).r;
			var targetSum = 1 - refValue;
			pixelColor = vec4(vec3((weightTextures.get(vec3(calculatedUV, curTexIndex)).rgb / sum) * targetSum), 1.0);

			if(baseTexIndex == curTexIndex){
				pixelColor = mix(vec4(1), vec4(refValue), ceil(min(1,sum)));
			}
		}
	}
}
