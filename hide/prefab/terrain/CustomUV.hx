package hide.prefab.terrain;

class CustomUV extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;
		@param var tileIndex : Float;

		@param var heightMapSize : Float;
		@param var heightMap : Sampler2D;
		@param var primSize : Float;

		var calculatedUV : Vec2;
		var terrainUV : Vec2;

		function vertex() {
			terrainUV = input.position.xy / primSize * (heightMapSize - 1) / heightMapSize + 0.5 / heightMapSize;
			calculatedUV = input.position.xy / primSize;
			transformedPosition += (vec3(0,0, heightMap.get(terrainUV).r) * global.modelView.mat3());
		}

		function fragment() {
			pixelColor = vec4(calculatedUV.x, calculatedUV.y, tileIndex , 1);
		}
	}
}
