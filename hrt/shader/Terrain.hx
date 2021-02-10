package hrt.shader;

class Terrain extends hxsl.Shader {

	static var SRC = {

		@const var SHOW_GRID : Bool;
		@const var SURFACE_COUNT : Int;
		@const var CHECKER : Bool;
		@const var COMPLEXITY : Bool;
		@const var PARALLAX : Bool;
		@const var VERTEX_DISPLACEMENT : Bool;

		@param var primSize : Vec2;
		@param var cellSize : Vec2;
		@param var heightMapSize : Vec2;

		@param var albedoTextures : Sampler2DArray;
		@param var normalTextures : Sampler2DArray;
		@param var pbrTextures : Sampler2DArray;
		/*
			We need to use a texture array so each blend factor is separate.
			This allows us to fetch in bilinear without worrying about interpolation
			between weights corresponding to different indexes.
		*/
		@param var weightTextures : Sampler2DArray;
		@param var surfaceIndexMap : Sampler2D;
		@param var heightMap : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var surfaceParams : Array<Vec4, SURFACE_COUNT>;
		@param var secondSurfaceParams : Array<Vec4, SURFACE_COUNT>;

		@param var heightBlendStrength : Float;
		@param var blendSharpness : Float;

		@param var parallaxAmount : Float;
		@param var minStep : Int;
		@param var maxStep : Int;
		@param var tileIndex : Vec2;

		var worldUV : Vec2;
		var calculatedUV : Vec2;
		var TBN : Mat3;

		var emissive : Float;
		var metalness : Float;
		var roughness : Float;
		var occlusion : Float;

		var tangentViewPos : Vec3;
		var tangentFragPos : Vec3;
		var transformedPosition : Vec3;
		var transformedNormal : Vec3;
		var terrainNormal : Vec3;
		var pixelColor : Vec4;

		@input var input : {
			var position : Vec3;
			var normal : Vec3;
		};

		@global var global : {
			@perObject var modelView : Mat4;
		};

		@global var camera : {
			var position : Vec3;
		};

		function vertex() {

			calculatedUV = input.position.xy / primSize;
			worldUV = transformedPosition.xy;

			if( VERTEX_DISPLACEMENT ) { // Use heightMap and normalMap
				transformedPosition += vec3(0, 0, textureLod(heightMap, calculatedUV, 0).r);
				terrainNormal = unpackNormal(textureLod(normalMap, calculatedUV, 0).rgba);
			}
			else { // The normal and height are in the vertex
				terrainNormal = normalize(input.normal * global.modelView.mat3());
			}

			// Make the TBN matrix for normal mapping and parallax
			var bitangent = normalize(cross(vec3(1, 0, 0), terrainNormal));
			var tangent = normalize(cross(terrainNormal, bitangent));
			TBN = mat3(	vec3(tangent.x, bitangent.x, terrainNormal.x),
						vec3(tangent.y, bitangent.y, terrainNormal.y),
						vec3(tangent.z, bitangent.z, terrainNormal.z));
		}

		function getWeight( i : IVec3,  uv : Vec2 ) : Vec3 {
			var weight = vec3(0);
			weight.x = weightTextures.getLod(vec3(uv, i.x), 0).r;
			if( i.y != i.x ) weight.y = weightTextures.getLod(vec3(uv, i.y), 0).r;
			if( i.z != i.x ) weight.z = weightTextures.getLod(vec3(uv, i.z), 0).r;
			return weight;
		}

		function getDepth( i : IVec3,  uv : Vec2 ) : Vec3 {
			var depth = vec3(0);
			if( w.x > 0 ) depth.x = pbrTextures.getLod(getsurfaceUV(i.x, uv), 0).a;
			if( w.y > 0 ) depth.y = pbrTextures.getLod(getsurfaceUV(i.y, uv), 0).a;
			if( w.z > 0 ) depth.z = pbrTextures.getLod(getsurfaceUV(i.z, uv), 0).a;
			return 1 - depth;
		}

		var w : Vec3;
		var i : IVec3;
		function getPOMUV( i : IVec3, uv : Vec2 ) : Vec2 {
			var viewNS = normalize(camera.position - transformedPosition) * TBN;
			viewNS.xy /= viewNS.z;
			viewNS.x *= -1;
			var numLayers = mix(float(maxStep), float(minStep), viewNS.dot(terrainNormal));
			var layerDepth = 1.0 / numLayers;
			var curLayerDepth = 0.;
			var delta = (viewNS.xy * parallaxAmount / primSize) / numLayers;
			var curUV = uv;
			var depth = getDepth(i, curUV);
			var curDepth = depth.dot(w);
			var prevDepth = 0.;
			while( curLayerDepth < curDepth ) {
				curUV += delta;
				prevDepth = curDepth;
				i = ivec3(surfaceIndexMap.getLod(curUV, 0).rgb * 255);
				w = getWeight(i, curUV);
				depth = getDepth(i, curUV);
				curDepth = depth.dot(w);
				curLayerDepth += layerDepth;
			}
			var prevUV = curUV - delta;
			var after = curDepth - curLayerDepth;
			var before = prevDepth - curLayerDepth + layerDepth;
			var pomUV = mix(curUV, prevUV,  after / (after - before));
			return pomUV;
		}

		function getsurfaceUV( id : Int, uv : Vec2 ) : Vec3 {
			uv = transformedPosition.xy + (uv * primSize - input.position.xy); // Local To world
			var angle = surfaceParams[id].w;
			var offset = vec2(surfaceParams[id].y, surfaceParams[id].z);
			var tilling = surfaceParams[id].x;
			var worldUV = uv * tilling + offset;
			var res = vec2( worldUV.x * cos(angle) - worldUV.y * sin(angle) , worldUV.y * cos(angle) + worldUV.x * sin(angle));
			var surfaceUV = vec3(res % 1, id);
			return surfaceUV;
		}

		function fragment() {

			if( CHECKER ) {
				var tile = abs(abs(floor(input.position.x)) % 2 - abs(floor(input.position.y)) % 2);
				pixelColor = vec4(mix(vec3(0.4), vec3(0.1), tile), 1.0);
				roughness = mix(0.1, 0.9, tile);
				metalness = mix(1.0, 0, tile);
				occlusion = 1;
				emissive = 0;
			}
			else if( COMPLEXITY ) {
				var blendCount = 0 + weightTextures.get(vec3(0)).r * 0;
				for(i in 0 ... SURFACE_COUNT)
					blendCount += ceil(weightTextures.get(vec3(calculatedUV, i)).r);
				pixelColor = vec4(mix(vec3(0,1,0), vec3(1,0,0), blendCount / 3.0) , 1);
				emissive = 1;
				roughness = 1;
				metalness = 0;
				occlusion = 1;
			}
			else {
				i = ivec3(surfaceIndexMap.get(calculatedUV).rgb * 255);
				w = getWeight(i, calculatedUV);
				var pomUV = PARALLAX ? getPOMUV(i, calculatedUV) : calculatedUV;
				if( PARALLAX ) {
					i = ivec3(surfaceIndexMap.get(pomUV).rgb * 255);
					w = getWeight(i, pomUV);
				}
				var h = vec3(0);
				var surfaceUV1 = getsurfaceUV(i.x, pomUV);
				var surfaceUV2 = getsurfaceUV(i.y, pomUV);
				var surfaceUV3 = getsurfaceUV(i.z, pomUV);
				var pbr1 = vec4(0), pbr2 = vec4(0), pbr3 = vec4(0);
				if( w.x > 0 ) pbr1 = pbrTextures.get(surfaceUV1).rgba;
				if( w.y > 0 ) pbr2 = pbrTextures.get(surfaceUV2).rgba;
				if( w.z > 0 ) pbr3 = pbrTextures.get(surfaceUV3).rgba;

				// Height Blend
				var h = vec3( 	secondSurfaceParams[i.x].x + pbr1.a * (secondSurfaceParams[i.x].y - secondSurfaceParams[i.x].x),
								secondSurfaceParams[i.y].x + pbr2.a * (secondSurfaceParams[i.y].y - secondSurfaceParams[i.y].x),
								secondSurfaceParams[i.z].x + pbr3.a * (secondSurfaceParams[i.z].y - secondSurfaceParams[i.z].x));

				var h = mix(vec3(1,1,1), h, heightBlendStrength);
				w *= h;

				// Sharpness
				var ws = mix(w, w, blendSharpness);
				var m = max(w.x, max(w.y, w.z));
				var mw = vec3(0,0,0);
				if( m == w.x ) mw = vec3(1,0,0);
				if( m == w.y ) mw = vec3(0,1,0);
				if( m == w.z ) mw = vec3(0,0,1);
				w = mix(w, mw, blendSharpness);

				// Blend
				var albedo = vec3(0);
				var normal = vec3(0);
				var pbr = vec4(0);
				if( w.x > 0 ) {
					albedo += albedoTextures.get(surfaceUV1).rgb * w.x;
					normal += unpackNormal(normalTextures.get(surfaceUV1).rgba) * w.x;
					pbr += pbr1 * w.x;
				}
				if( w.y > 0 ) {
					albedo += albedoTextures.get(surfaceUV2).rgb * w.y;
					normal += unpackNormal(normalTextures.get(surfaceUV2).rgba) * w.y;
					pbr += pbr2 * w.y;
				}
				if( w.z > 0 ) {
					albedo += albedoTextures.get(surfaceUV3).rgb * w.z;
					normal += unpackNormal(normalTextures.get(surfaceUV3).rgba) * w.z;
					pbr += pbr3 * w.z;
				}
				var wSum = w.x + w.y + w.z;
				albedo /= wSum;
				pbr /= wSum;
				normal /= wSum;
				normal = normal.normalize();

				// Output
				transformedNormal = normalize(normal * TBN);
				pixelColor = vec4(albedo, 1.0);
				roughness = 1 - pbr.g * pbr.g;
				metalness = pbr.r;
				occlusion = pbr.b;
				emissive = 0;
			}

			if( SHOW_GRID ) {
				var gridColor = vec4(1,0,0,1);
				var tileEdgeColor = vec4(1,1,0,1);
				var grid : Vec2 = ((input.position.xy.mod(cellSize.xy) / cellSize.xy ) - 0.5) * 2.0;
				grid = ceil(max(vec2(0), abs(grid) - 0.9));
				var tileEdge = max( (1 - ceil(input.position.xy / primSize - 0.1 / (primSize / cellSize) )), floor(input.position.xy / primSize + 0.1 / (primSize / cellSize)));
				emissive = max(max(grid.x, grid.y), max(tileEdge.x, tileEdge.y));
				pixelColor = mix( pixelColor, gridColor, clamp(0,1,max(grid.x, grid.y)));
				pixelColor = mix( pixelColor, tileEdgeColor, clamp(0,1,max(tileEdge.x, tileEdge.y)));
				metalness =  mix(metalness, 0, emissive);
				roughness = mix(roughness, 1, emissive);
				occlusion = mix(occlusion, 1, emissive);
				transformedNormal = mix(transformedNormal, vec3(0,1,0), emissive);
			}
		}
	};

}

