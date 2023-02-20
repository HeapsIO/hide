package hide.prefab2.terrain;

class GenerateIndex extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var weightTextures : Sampler2DArray;
		@param var weightCount : Int;
		@param var mask : Array<Vec4, 4>;

		function fragment() {
			var indexes = vec4(0,0,0,1);
			var curMask = 0;
			for(i in 0 ... weightCount){
				var w = weightTextures.get(vec3(calculatedUV, i)).r;
				if( w > 0 && curMask < 3){
					indexes += mask[curMask] * i / 255.0;
					curMask++;
				}
			}
			pixelColor = indexes;
		}
	}

	public function new(){
		super();
		mask = [new h3d.Vector(1,0,0,0), new h3d.Vector(0,1,0,0), new h3d.Vector(0,0,1,0), new h3d.Vector(0,0,0,1)];
	}
}
