package hrt.prefab.terrain;
import h3d.pass.ScreenFx;
using Lambda;

class TerrainCopy extends h3d.shader.ScreenShader {
	static var SRC = {

		@param var from : Vec2;
		@param var to : Vec2;
		@param var source : Sampler2D;

		function vertex() {
			output.position = vec4(uvToScreen(mix(from, to, screenToUv(input.position))), 0, 1);
			output.position.y *= flipY;
		}

		function fragment() {
			pixelColor = source.get(calculatedUV);
		}
	}
}

@:access(hrt.prefab.terrain.TerrainMesh)
@:access(hrt.prefab.terrain.Tile)
class TerrainResize {

	public function new( ) {

	}

	static inline function getTileBounds( xi, yi, s : h2d.col.Point ) : h2d.col.Bounds {
		var b = new h2d.col.Bounds();
		b.xMin = xi * s.x; 
		b.yMin = yi * s.y;
		b.xMax = (xi + 1) * s.x;
		b.yMax = (yi + 1) * s.y;
		return b;
	}

	static public function resize( prefab : Terrain, tileSize : h2d.col.Point ) {

		if( prefab.terrain.tileSize.x == tileSize.x && prefab.terrain.tileSize.y == tileSize.y )
			return;

		var engine = h3d.Engine.getCurrent();
		var terrainCopy = new ScreenFx(new TerrainCopy());

		var prevTiles = prefab.terrain.tiles;
		var prevSize = prefab.terrain.tileSize;
		var curSize = tileSize;

		// Recreate tiles to fit with the new size
		var terrainMinMax = new h3d.Vector();
		terrainMinMax.set(hxd.Math.POSITIVE_INFINITY, hxd.Math.POSITIVE_INFINITY, hxd.Math.NEGATIVE_INFINITY);
		for( t in prefab.terrain.tiles ) {
			terrainMinMax.x = hxd.Math.min(terrainMinMax.x, t.tileX * prevSize.x);
			terrainMinMax.y = hxd.Math.min(terrainMinMax.y, t.tileY * prevSize.y);
			terrainMinMax.z = hxd.Math.max(terrainMinMax.z, (t.tileX + 1) * prevSize.x);
			terrainMinMax.w = hxd.Math.max(terrainMinMax.w, (t.tileY + 1) * prevSize.y);
		}
		var terrainBounds : Array<h2d.col.Bounds> = [];
		var bias = 0.1;
		for( t in prefab.terrain.tiles ) {
			var b = new h2d.col.Bounds();
			b.xMin = t.tileX * prevSize.x + bias;
			b.yMin = t.tileY * prevSize.y + bias;
			b.xMax = (t.tileX + 1) * prevSize.x - bias;
			b.yMax = (t.tileY + 1) * prevSize.y - bias;
			terrainBounds.push(b);
		}
		prefab.terrain.tiles = [];
		prefab.terrain.tileSize = tileSize;
		var x = terrainMinMax.x;
		var y = terrainMinMax.y;
		var tmpBounds = new h2d.col.Bounds();
		while( x < terrainMinMax.z ) {
			while( y < terrainMinMax.w ) {

				tmpBounds.xMin = x;
				tmpBounds.yMin = y;
				tmpBounds.xMax = x + curSize.x;
				tmpBounds.yMax = y + curSize.y;
				var intersectTerrain = false;
				for( b in terrainBounds ) {
					if( b.intersects(tmpBounds) ) {
						intersectTerrain = true;
						break;
					}
				}
				if( intersectTerrain )
					prefab.terrain.createTile(Std.int(x / curSize.x), Std.int(y / curSize.y));

				y += curSize.y;
			}
			y = terrainMinMax.y;
			x += curSize.x;
		}	

		// Copy Textures
		for( curTile in prefab.terrain.tiles ) {
			var curTileBounds = getTileBounds(curTile.tileX, curTile.tileY, curSize);
			for( prevTile in prevTiles ) {

				var prevTileBounds = getTileBounds(prevTile.tileX, prevTile.tileY, prevSize);
				if( !prevTileBounds.intersects(curTileBounds) ) 
					continue;
				
				terrainCopy.shader.from.set((prevTileBounds.x - curTileBounds.x) / curTileBounds.width, (prevTileBounds.y - curTileBounds.y) / curTileBounds.height);
				terrainCopy.shader.to.set(terrainCopy.shader.from.x + prevTileBounds.width / curTileBounds.width, terrainCopy.shader.from.y + prevTileBounds.height / curTileBounds.height );

				// Copy HeightMap
				engine.pushTarget(curTile.heightMap);
				terrainCopy.shader.source = prevTile.heightMap;
				terrainCopy.render();
				engine.popTarget();

				// Copy NormalMap
				engine.pushTarget(curTile.normalMap);
				terrainCopy.shader.source = prevTile.normalMap;
				terrainCopy.render();
				engine.popTarget();

				// Copy Index Map
				engine.pushTarget(curTile.surfaceIndexMap);
				terrainCopy.shader.source = prevTile.surfaceIndexMap;
				terrainCopy.render();
				engine.popTarget();

				// Copy Weight Map
				for( i in 0 ... curTile.surfaceWeightArray.layerCount ) {
					engine.pushTarget(curTile.surfaceWeights[i]);
					terrainCopy.shader.source = prevTile.surfaceWeights[i];
					terrainCopy.render();
					engine.popTarget();
					engine.pushTarget(curTile.surfaceWeightArray, i);
					terrainCopy.render();
					engine.popTarget();
				}
			}
		}

		// Dispose old tiles
		for( t in prevTiles ) {
			t.remove();
		}
	}

}