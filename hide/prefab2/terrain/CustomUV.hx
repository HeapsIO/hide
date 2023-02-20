package hide.prefab2.terrain;

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
			calculatedUV = input.position.xy / primSize.xy;
			transformedPosition += (vec3(0,0, heightMap.get(calculatedUV).r) * global.modelView.mat3());
			transformedNormal = vec3(0,0,0);
		}

		function fragment() {
			pixelColor = vec4(calculatedUV.x, calculatedUV.y, tileIndex , 1);
		}
	}
}
