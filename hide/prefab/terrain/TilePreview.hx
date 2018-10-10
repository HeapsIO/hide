package hide.prefab.terrain;

class TilePreview extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;
		@param var heightMap : Sampler2D;
		@param var heightMapSize : Float;
		@param var primSize : Float;

		@param var brushTex : Sampler2D;
		@param var brushSize : Float;
		@param var brushPos : Vec2;

		function vertex() {
			var calculatedUV = input.position.xy / primSize;
			var terrainUV = (calculatedUV * (heightMapSize - 1)) / heightMapSize;
			terrainUV += 0.5 / heightMapSize;
			transformedPosition += (vec3(0,0, heightMap.get(terrainUV).r) * global.modelView.mat3());
		}

		function fragment() {
			var tilePos = (input.position.xy / primSize);
			var brushUV = tilePos - (brushPos - (brushSize / (2.0 * primSize)));
			brushUV /= (brushSize / primSize);
			pixelColor = vec4(brushTex.get(brushUV).r * vec3(1,1,1), min(0.7,brushTex.get(brushUV).r));

			if(brushUV.x < 0 || brushUV.x > 1 || brushUV.y < 0 || brushUV.y > 1 )
				pixelColor = vec4(0);

		}
	}
}
