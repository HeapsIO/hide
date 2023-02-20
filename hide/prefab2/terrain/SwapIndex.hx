package hide.prefab2.terrain;

class SwapIndex extends h3d.shader.ScreenShader {

	static var SRC = {

		@const var USE_ARRAY : Bool;
		@const var INDEX_COUNT : Int;
		@param var surfaceIndexMap : Sampler2D;
		@param var oldIndex : Int;
		@param var newIndex : Int;
		@param var oldIndexes : Array<Vec4, INDEX_COUNT>;
		@param var newIndexes : Array<Vec4, INDEX_COUNT>;

		function fragment() {
			var indexes = surfaceIndexMap.get(calculatedUV);
			var i1 = int(indexes.r * 255);
			var i2 = int(indexes.g * 255);
			var i3 = int(indexes.b * 255);
			if(USE_ARRAY){
				for(i in 0 ... INDEX_COUNT){
					if(i1 == int(oldIndexes[i].r)) i1 = int(newIndexes[i].r);
					if(i2 == int(oldIndexes[i].r)) i2 = int(newIndexes[i].r);
					if(i3 == int(oldIndexes[i].r)) i3 = int(newIndexes[i].r);
				}
			}
			else {
				if(i1 == oldIndex) i1 = newIndex;
				if(i2 == oldIndex) i2 = newIndex;
				if(i3 == oldIndex) i3 = newIndex;
			}
			pixelColor = vec4(i1 / 255, i2 / 255, i3 / 255, 1);
		}
	}

	public function new(){
		super();
		this.USE_ARRAY = false;
	}
}
