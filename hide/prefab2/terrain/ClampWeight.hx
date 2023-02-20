package hide.prefab2.terrain;

class ClampWeight extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var weightTextures : Sampler2DArray;
		@param var weightCount : Int;
		@param var baseTexIndex : Int;
		@param var curTexIndex : Int;

		function fragment() {
			var count = 0;
			var smallestWeightIndex = -1;
			var smallestWeight = 1.0;
			for(i in 0 ... weightCount){
				var w = weightTextures.get(vec3(calculatedUV, i)).r;
				if(w > 0.0){
					count++;
					if(i != baseTexIndex && smallestWeight > w){
						smallestWeight = w;
						smallestWeightIndex = i;
					}
				}
			}
			pixelColor = weightTextures.get(vec3(calculatedUV, curTexIndex)).rgba;
			if(count > 3 && curTexIndex == smallestWeightIndex)
				pixelColor = vec4(0);
		}
	}
}
