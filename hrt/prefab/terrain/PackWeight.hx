package hrt.prefab.terrain;

class PackWeight extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var indexMap : Sampler2D;
		@param var weightTextures : Sampler2DArray;
		@param var weightCount : Int;
		@param var mask : Array<Vec4, 4>;

		function fragment() {
			pixelColor = vec4(0,0,0,1);
			var curMaskIndex = 0;
			for(i in 0 ... weightCount){
				var w = weightTextures.get(vec3(calculatedUV, i)).r;
				if( w > 0 && curMaskIndex < 3){
					pixelColor += mask[curMaskIndex] * w;
					curMaskIndex++;
				}
			}

			/*var texIndex = indexMap.get(calculatedUV).rgb;
			var i1 : Int = int(texIndex.r * 255);
			var i2 : Int = int(texIndex.g * 255);
			var i3 : Int = int(texIndex.b * 255);
			pixelColor = vec4(weightTextures.get(vec3(calculatedUV, i1)).r, weightTextures.get(vec3(calculatedUV, i2)).r, weightTextures.get(vec3(calculatedUV, i3)).r, 0);*/
		}
	}

	public function new(){
		super();
		mask = [new h3d.Vector(1,0,0,0), new h3d.Vector(0,1,0,0), new h3d.Vector(0,0,1,0), new h3d.Vector(0,0,0,1)];
	}
}
