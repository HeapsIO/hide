package hide.prefab.terrain;

class CustomUV extends hxsl.Shader {

	static var SRC = {

		@:import h3d.shader.BaseMesh;
		@param var tileIndex : Float;

		@param var heightMapSize : Vec2;
		@param var heightMap : Sampler2D;
		@param var primSize : Vec2;

		var calculatedUV : Vec2;
		var terrainUV : Vec2;

		function vertex() {
			terrainUV = input.position.xy / primSize.xy * (heightMapSize.xy - 1) / heightMapSize.xy + 0.5 / heightMapSize.xy;
			calculatedUV = input.position.xy / primSize.xy;
			transformedPosition += (vec3(0,0, heightMap.get(terrainUV).r) * global.modelView.mat3());
		}

		function fragment() {
			pixelColor = vec4(calculatedUV.x, calculatedUV.y, tileIndex , 1);
		}
	}
}
