package hide.prefab.terrain;

class UnpackWeight extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var indexMap : Sampler2D;
		@param var packedWeightTexture : Sampler2D;
		@param var index : Int;

		function fragment() {
			pixelColor = vec4(0,0,0,1);
			var texIndex = indexMap.get(calculatedUV).rgb;
			var i1 : Int = int(texIndex.r * 255);
			var i2 : Int = int(texIndex.g * 255);
			var i3 : Int = int(texIndex.b * 255);
			if(i1 == index) pixelColor = vec4(vec3(packedWeightTexture.get(calculatedUV).r), 1.0);
			else if(i2 == index) pixelColor = vec4(vec3(packedWeightTexture.get(calculatedUV).g), 1.0);
			else if(i3 == index) pixelColor = vec4(vec3(packedWeightTexture.get(calculatedUV).b), 1.0);
		}
	}
}
