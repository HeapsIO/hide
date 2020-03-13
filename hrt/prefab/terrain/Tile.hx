package hrt.prefab.terrain;

import h3d.prim.Grid;

enum Direction{
	Up; Down; Left; Right; UpLeft; UpRight; DownLeft; DownRight;
}

@:access(hrt.prefab.terrain.TerrainMesh)
class Tile extends h3d.scene.Mesh {

	public var tileX (default, null) : Int;
	public var tileY (default, null) : Int;
	public var heightMap(default, set) : h3d.mat.Texture;
	public var surfaceIndexMap : h3d.mat.Texture;
	public var surfaceWeights : Array<h3d.mat.Texture> = [];
	public var surfaceWeightArray (default, null) : h3d.mat.TextureArray;
	public var grid (default, null) : h3d.prim.Grid;
	public var needAlloc = false;
	public var needNewPixelCapture = false;
	public var insideFrustrum(default, null) = false;

	// set by prefab loader for CPU access ingame
	public var packedWeightMapPixel : hxd.Pixels;
	public var indexMapPixels : hxd.Pixels;
	public var normalTangentBytes : haxe.io.Bytes;

	var heightmapPixels : hxd.Pixels.PixelsFloat;
	var shader : hrt.shader.Terrain;
	var terrain : TerrainMesh;
	var bigPrim : h3d.prim.BigPrimitive;

	public function new( x : Int, y : Int, parent : TerrainMesh) {
		super(null, null, parent);
		terrain = parent;
		this.tileX = x;
		this.tileY = y;
		shader = new hrt.shader.Terrain();
		material.mainPass.addShader(shader);
		material.mainPass.culling = Back;
		this.x = x * terrain.tileSize.x;
		this.y = y * terrain.tileSize.y;
		name = "tile_" + x + "_" + y;
		material.mainPass.setPassName("terrain");
	}

	override function onRemove() {
		super.onRemove();
		if( heightMap != null )
			heightMap.dispose();
		if( surfaceIndexMap != null )
			surfaceIndexMap.dispose();
		for( i in 0 ... surfaceWeights.length )
			if( surfaceWeights[i] != null ) surfaceWeights[i].dispose();
		if( surfaceWeightArray != null )
			surfaceWeightArray.dispose();
		if( bigPrim != null )
			bigPrim.dispose();
		if(packedWeightMapPixel != null)
			packedWeightMapPixel.dispose();
		if(indexMapPixels != null)
			indexMapPixels.dispose();
		if(heightmapPixels != null)
			heightmapPixels.dispose();
		normalTangentBytes = null;

	}

	function set_heightMap( v ) {
		shader.heightMap = v;
		return heightMap = v;
	}

	public function getHeightPixels() {
		if( needNewPixelCapture || heightmapPixels == null && heightMap != null )
			heightmapPixels = heightMap.capturePixels();
		needNewPixelCapture = false;
		return heightmapPixels;
	}

	public function createBigPrim( bytes : haxe.io.Bytes ) {

		var stride = 3 * 4 + 3 * 4; // Normal + Tangent
		var vertexCount = (terrain.cellCount.x + 1) * (terrain.cellCount.y + 1);
		if( bytes.length != stride * vertexCount ) {
			throw "Bytes length doesn't match with the size of tiles";
			return;
		}

		if( bigPrim != null )
			bigPrim.dispose();

		normalTangentBytes = bytes;
		bigPrim = new h3d.prim.BigPrimitive(9, true);
		inline function addVertice(x : Float, y : Float, i : Int) {
			// Pos
			bigPrim.addPoint(x, y, getHeight(x / terrain.tileSize.x, y / terrain.tileSize.y)); // Use addPoint() instead of addVertexValue() for the bounds
			// Normal
			bigPrim.addVertexValue(bytes.getFloat(i * stride));
			bigPrim.addVertexValue(bytes.getFloat(i * stride + 4));
			bigPrim.addVertexValue(bytes.getFloat(i * stride + 8));
			// Tangents
			bigPrim.addVertexValue(bytes.getFloat(i * stride + 12));
			bigPrim.addVertexValue(bytes.getFloat(i * stride + 16));
			bigPrim.addVertexValue(bytes.getFloat(i * stride + 20));
		}

		var cellCount = terrain.cellCount;
		var cellSize = terrain.cellSize;
		bigPrim.begin(0,0);
		for( y in 0 ... cellCount.y + 1 ) {
			for( x in 0 ... cellCount.x + 1 ) {
				addVertice(x * cellSize.x, y * cellSize.y, x + y * (terrain.cellCount.x + 1));
			}
		}

		for( y in 0 ... cellCount.y ) {
			for( x in 0 ... cellCount.x ) {
				var i = x + y * (cellCount.x + 1);
				bigPrim.addIndex(i);
				bigPrim.addIndex(i + 1);
				bigPrim.addIndex(i + cellCount.x + 2);
				bigPrim.addIndex(i);
				bigPrim.addIndex(i + cellCount.x + 2);
				bigPrim.addIndex(i + cellCount.x + 1);
			}
		}
		bigPrim.flush();
		primitive = bigPrim;
	}

	public function refreshGrid() {
		if( bigPrim != null )
			return;
		if( grid == null || grid.width != terrain.cellCount.x || grid.height != terrain.cellCount.y || grid.cellWidth != terrain.cellSize.x || grid.cellHeight != terrain.cellSize.y ) {
			if( grid != null ) grid.dispose();
		 	grid = new h3d.prim.Grid(terrain.cellCount.x, terrain.cellCount.y, terrain.cellSize.x, terrain.cellSize.y);
			primitive = grid;
		}
		computeHeight();
		computeNormals();
		computeTangents();
	}

	public function blendEdges() {
		var adjTileX = terrain.getTile(tileX - 1, tileY);
		if( adjTileX != null ) {
			var flags = new haxe.EnumFlags<Direction>();
        	flags.set(Left);
			adjTileX.computeEdgesHeight(flags);
		}
		var adjTileY = terrain.getTile(tileX, tileY - 1);
		if( adjTileY != null ) {
			var flags = new haxe.EnumFlags<Direction>();
        	flags.set(Up);
			adjTileY.computeEdgesHeight(flags);
		}
		var adjTileXY = terrain.getTile(tileX - 1, tileY - 1);
		if( adjTileXY != null ) {
			var flags = new haxe.EnumFlags<Direction>();
        	flags.set(UpLeft);
			adjTileXY.computeEdgesHeight(flags);
		}
		var flags = new haxe.EnumFlags<Direction>();
        flags.set(Left);
		flags.set(Up);
		flags.set(UpLeft);

		computeHeight();
		computeEdgesHeight(flags);
		computeNormals();
		computeEdgesNormals();
		computeTangents();
	}

	function refreshHeightMap() {
		if( heightMap == null || heightMap.width != terrain.heightMapResolution.x + 1 || heightMap.height != terrain.heightMapResolution.y + 1 ) {
			var oldHeightMap = heightMap;
			heightMap = new h3d.mat.Texture(terrain.heightMapResolution.x + 1, terrain.heightMapResolution.y + 1, [Target], RGBA32F );
			heightMap.setName("terrainHeightMap");
			heightMap.wrap = Clamp;
			heightMap.filter = Linear;
			heightMap.preventAutoDispose();

			heightMap.realloc = function() {
				heightMap.uploadPixels(heightmapPixels);
			}

			if( oldHeightMap != null ) {
				terrain.copyPass.apply(oldHeightMap, heightMap);
				oldHeightMap.dispose();
			}
			needNewPixelCapture = true;
		}
	}

	function refreshIndexMap() {
		if( surfaceIndexMap == null || surfaceIndexMap.width != terrain.weightMapResolution.x || surfaceIndexMap.height != terrain.weightMapResolution.y ) {
			var oldSurfaceIndexMap = surfaceIndexMap;
			surfaceIndexMap = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target], RGBA);
			surfaceIndexMap.setName("terrainSurfaceIndexMap");
			surfaceIndexMap.filter = Nearest;
			surfaceIndexMap.preventAutoDispose();

			surfaceIndexMap.realloc = function() {
				surfaceIndexMap.uploadPixels(indexMapPixels);
			}

			if( oldSurfaceIndexMap != null ) {
				terrain.copyPass.apply(oldSurfaceIndexMap, surfaceIndexMap);
				oldSurfaceIndexMap.dispose();
			}
		}
	}

	function refreshSurfaceWeightArray() {
		if( terrain.surfaceArray.surfaceCount > 0 && (surfaceWeights.length != terrain.surfaceArray.surfaceCount || surfaceWeights[0].width != terrain.weightMapResolution.x || surfaceWeights[0].height != terrain.weightMapResolution.y) ) {
				var oldArray = surfaceWeights;
				surfaceWeights = new Array<h3d.mat.Texture>();
				surfaceWeights = [for( i in 0...terrain.surfaceArray.surfaceCount ) null];
				for( i in 0 ... surfaceWeights.length ) {
					surfaceWeights[i] = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target], R8);
					surfaceWeights[i].setName("terrainSurfaceWeight"+i);
					surfaceWeights[i].wrap = Clamp;
					surfaceWeights[i].preventAutoDispose();
					if( i < oldArray.length && oldArray[i] != null )
						terrain.copyPass.apply(oldArray[i], surfaceWeights[i]);
				}
				for( t in oldArray )
					if( t != null)
						t.dispose();
		}
	}

	function disposeSurfaceWeightArray() {
		if( surfaceWeights != null ) {
			for( t in surfaceWeights )
				if( t != null ) t.dispose();
		}
	}

	public function refreshTex() {
		refreshHeightMap();
		refreshIndexMap();
		refreshSurfaceWeightArray();
		generateWeightTextureArray();
	}

	public function generateWeightTextureArray() {
		if( surfaceWeightArray == null || surfaceWeightArray.width != terrain.weightMapResolution.x || surfaceWeightArray.height != terrain.weightMapResolution.y || surfaceWeightArray.layerCount != terrain.surfaceArray.surfaceCount  ) {
			if( surfaceWeightArray != null ) surfaceWeightArray.dispose();
			surfaceWeightArray = new h3d.mat.TextureArray(terrain.weightMapResolution.x, terrain.weightMapResolution.y, terrain.surfaceArray.surfaceCount, [Target], R8);
			surfaceWeightArray.setName("terrainSurfaceWeightArray");
			surfaceWeightArray.wrap = Clamp;
			surfaceWeightArray.preventAutoDispose();

			// OnContextLost support : Restore the textureArray with the pixels from the packedWeight texture
			surfaceWeightArray.realloc = function() {
				var engine = h3d.Engine.getCurrent();
				var unpackWeight = new h3d.pass.ScreenFx(new UnpackWeight());
				var tmpPackedWeightTexture = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target]);
				tmpPackedWeightTexture.uploadPixels(packedWeightMapPixel);
				for( i in 0 ... surfaceWeightArray.layerCount ) {
					engine.pushTarget(surfaceWeightArray, i);
					unpackWeight.shader.indexMap = surfaceIndexMap;
					unpackWeight.shader.packedWeightTexture = tmpPackedWeightTexture;
					unpackWeight.shader.index = i;
					unpackWeight.render();
					engine.popTarget();
				}
			}
		}
		for( i in 0 ... surfaceWeights.length )
			if( surfaceWeights[i] != null ) terrain.copyPass.apply(surfaceWeights[i], surfaceWeightArray, None, null, i);
	}

	public function computeHeight() {
		for( p in grid.points ) {
			p.z = getHeight(p.x / terrain.tileSize.x, p.y / terrain.tileSize.y);
		}
		needAlloc = true;
		return;
	}

	public function computeEdgesHeight( flag : haxe.EnumFlags<Direction> ) {

		if( heightMap == null ) return;
		var pixels : hxd.Pixels.PixelsFloat = getHeightPixels();

		if( flag.has(Left) ) {
			var adjTileX = terrain.getTile(tileX + 1, tileY);
			var adjHeightMapX = adjTileX != null ? adjTileX.heightMap : null;
			if( adjHeightMapX != null ) {
				var adjpixels : hxd.Pixels.PixelsFloat = adjTileX.getHeightPixels();
				for( i in 0 ... heightMap.height - 1 ) {
					pixels.setPixelF(heightMap.width - 1, i, adjpixels.getPixelF(0,i) );
				}
			}
		}
		if( flag.has(Up) ) {
			var adjTileY = terrain.getTile(tileX, tileY + 1);
			var adjHeightMapY = adjTileY != null ? adjTileY.heightMap : null;
			if( adjHeightMapY != null ) {
				var adjpixels : hxd.Pixels.PixelsFloat = adjTileY.getHeightPixels();
				for( i in 0 ... heightMap.width - 1) {
					pixels.setPixelF(i, heightMap.height - 1, adjpixels.getPixelF(i,0) );
				}
			}
		}
		if( flag.has(UpLeft) ) {
			var adjTileXY = terrain.getTile(tileX + 1, tileY + 1);
			var adjHeightMapXY = adjTileXY != null ? adjTileXY.heightMap : null;
			if( adjHeightMapXY != null ) {
				var adjpixels : hxd.Pixels.PixelsFloat = adjTileXY.getHeightPixels();
				pixels.setPixelF(heightMap.width - 1, heightMap.height - 1, adjpixels.getPixelF(0,0));
			}
		}
		heightmapPixels = pixels;
		heightMap.uploadPixels(pixels);
		needNewPixelCapture = false;
	}

	public function computeEdgesNormals() {

		if( grid.normals == null ) 
			return;


		inline function isEdgeIndex( grid : Grid, i : Int, side : Int ) : Bool {
			var v = grid.points[grid.idx[i]];
			return switch( side ) {
				case 0: v.x == grid.width; // Left
				case 1: v.y == grid.height; // Up
				case 2:	v.y == 0; // Down
				case 3: v.x == 0; // Right
				default: false;
			}
		}
		// Need to recompute the normal before any blend
		inline function computeNormal( grid : Grid, index : Int,  assignOnSide : Int = -1 ) : h3d.col.Point {
			var n1 = grid.points[grid.idx[index+1]].sub(grid.points[grid.idx[index]]).normalize();
			var n2 = grid.points[grid.idx[index+2]].sub(grid.points[grid.idx[index]]).normalize();
			var n = n1.cross(n2).normalize();
			if( isEdgeIndex(grid, index, assignOnSide) ) grid.normals[grid.idx[index]] = grid.normals[grid.idx[index]].add(n);
			if( isEdgeIndex(grid, index+1, assignOnSide) ) grid.normals[grid.idx[index+1]] = grid.normals[grid.idx[index+1]].add(n);
			if( isEdgeIndex(grid, index+2, assignOnSide) ) grid.normals[grid.idx[index+2]] = grid.normals[grid.idx[index+2]].add(n);
			return n;
		}
		
		var widthVertexCount = grid.width + 1;
		var heightVertexCount = grid.height + 1;
		var widthTriangleCount = grid.width * 2;
		var heightTriangleCount = grid.height * 2;
		
		var adjUpTile = terrain.getTile(tileX, tileY + 1);
		var adjUpGrid = adjUpTile != null ? adjUpTile.grid : null;
		if( adjUpGrid != null && adjUpGrid.normals != null ) {
			for( i in 0 ... widthVertexCount ) 
				adjUpGrid.normals[i].set(0,0,0);
			for( i in 0 ... widthTriangleCount ) 
				computeNormal(adjUpGrid, i * 3, 2);
			for( i in 0 ... widthVertexCount ) {
				adjUpGrid.normals[i].normalize();
				var n = grid.normals[i + widthVertexCount * (heightVertexCount - 1)].add(adjUpGrid.normals[i]).normalize();
				grid.normals[i + widthVertexCount * (heightVertexCount - 1)].load(n);
				adjUpGrid.normals[i].load(n);
			}
			adjUpTile.needAlloc = true;
		}

		var adjDownTile = terrain.getTile(tileX, tileY - 1);
		var adjDownGrid = adjDownTile != null ? adjDownTile.grid : null;
		if( adjDownGrid != null && adjDownGrid.normals != null ) {
			for( i in 0 ... widthVertexCount ) 
				adjDownGrid.normals[i + widthVertexCount * (heightVertexCount - 1)].set(0,0,0);
			for( i in 0 ... widthTriangleCount ) 
				computeNormal(adjDownGrid, i * 3 + widthTriangleCount * 3 * (grid.height - 1), 1);
			for( i in 0 ... widthVertexCount ) {
				adjDownGrid.normals[i + widthVertexCount * (heightVertexCount - 1)].normalize();
				var n = grid.normals[i].add(adjDownGrid.normals[i + widthVertexCount * (heightVertexCount - 1)]).normalize();
				grid.normals[i].load(n);
				adjDownGrid.normals[i + widthVertexCount * (heightVertexCount - 1)].load(n);
			}
			adjDownTile.needAlloc = true;
		}

		var adjLeftTile = terrain.getTile(tileX + 1, tileY);
		var adjLeftGrid = adjLeftTile != null ? adjLeftTile.grid : null;
		if( adjLeftGrid != null && adjLeftGrid.normals != null ) {
			for( i in 0 ... heightVertexCount ) 
				adjLeftGrid.normals[i * widthVertexCount].set(0,0,0);
			for( i in 0 ... grid.height ) {
				computeNormal(adjLeftGrid, i * widthTriangleCount * 3, 0);
				computeNormal(adjLeftGrid, i * widthTriangleCount * 3 + 3, 3);
			}
			for( i in 0 ... heightVertexCount ) {
				adjLeftGrid.normals[i * widthVertexCount].normalize();
				var n = grid.normals[(widthVertexCount - 1) + i * widthVertexCount].add(adjLeftGrid.normals[i * widthVertexCount]).normalize();
				grid.normals[(widthVertexCount - 1) + i * widthVertexCount].load(n);
				adjLeftGrid.normals[i * widthVertexCount].load(n);
			}
			adjLeftTile.needAlloc = true;
		}

		var adjRightTile = terrain.getTile(tileX - 1, tileY);
		var adjRightGrid = adjRightTile != null ? adjRightTile.grid : null;
		if( adjRightGrid != null && adjRightGrid.normals != null ) {
			for( i in 0 ... heightVertexCount ) 
				adjRightGrid.normals[(widthVertexCount - 1) + i * widthVertexCount].set(0,0,0);
			for( i in 0 ... grid.height ) {
				computeNormal(adjRightGrid, (widthTriangleCount - 1) * 3 + i * widthTriangleCount * 3, 0);
				computeNormal(adjRightGrid, (widthTriangleCount - 2) * 3 + i * widthTriangleCount * 3, 0);
			}
			for( i in 0 ... heightVertexCount ) {
				adjRightGrid.normals[(widthVertexCount - 1) + i * widthVertexCount].normalize();
				var n = grid.normals[i * widthVertexCount].add(adjRightGrid.normals[(widthVertexCount - 1) + i * widthVertexCount]).normalize();
				grid.normals[i * widthVertexCount].load(n);
				adjRightGrid.normals[(widthVertexCount - 1) + i * widthVertexCount].load(n);
			}
			adjRightTile.needAlloc = true;
		}
		
		var adjUpRightTile = terrain.getTile(tileX - 1, tileY + 1);
		var adjUpRightGrid = adjUpRightTile != null ? adjUpRightTile.grid : null;
		var adjUpLeftTile = terrain.getTile(tileX + 1, tileY + 1);
		var adjUpLeftGrid = adjUpLeftTile != null ? adjUpLeftTile.grid : null;
		var adjDownLeftTile = terrain.getTile(tileX + 1, tileY - 1);
		var adjDownLeftGrid = adjDownLeftTile != null ? adjDownLeftTile.grid : null;
		var adjDownRightTile = terrain.getTile(tileX - 1, tileY - 1);
		var adjDownRightGrid = adjDownRightTile != null ? adjDownRightTile.grid : null;

		var upLeft = grid.points.length - 1;
		var downRight = 0;
		var downLeft = grid.width;
		var upRight = (grid.width + 1) * (grid.height);
		var n = new h3d.col.Point();

		inline function computeUpLeftNormal( grid : Grid ) : h3d.col.Point {
			return grid == null ? new h3d.col.Point() : computeNormal(grid, ((widthTriangleCount - 1) + (grid.height - 1) * widthTriangleCount) * 3);
		}
		inline function computeDownLeftNormal( grid : Grid ) : h3d.col.Point {
			return grid == null ? new h3d.col.Point() : computeNormal(grid, (heightTriangleCount - 1) * 3).add(computeNormal(grid, (heightTriangleCount - 2) * 3));
		}
		inline function computeUpRightNormal( grid : Grid ) : h3d.col.Point {
			return grid == null ? new h3d.col.Point() : computeNormal(grid, (grid.height - 1) * widthTriangleCount * 3).add(computeNormal(grid, (grid.height - 1) * widthTriangleCount * 3 + 3));
		}
		inline function computeDownRightNormal( grid : Grid ) : h3d.col.Point {
			return grid == null ? new h3d.col.Point() : computeNormal(grid, 0);
		}
		
		// Up Right Corner
		n.set(0,0,0);
		n = n.add(computeDownLeftNormal(adjUpRightGrid));
		n = n.add(computeUpLeftNormal(adjRightGrid));
		n = n.add(computeDownRightNormal(adjUpGrid));
		n = n.add(computeUpRightNormal(grid));
		n.normalize();
		if(	adjUpRightGrid != null ) adjUpRightGrid.normals[downLeft].load(n);
		if( adjRightGrid != null ) adjRightGrid.normals[upLeft].load(n);
		if( adjUpGrid != null ) adjUpGrid.normals[downRight].load(n);
		grid.normals[upRight].load(n);
		if( adjUpRightTile != null ) adjUpRightTile.needAlloc = true;

		// Up Left Corner
		n.set(0,0,0);
		n = n.add(computeDownLeftNormal(adjUpGrid));
		n = n.add(computeUpLeftNormal(grid));
		n = n.add(computeDownRightNormal(adjUpLeftGrid));
		n = n.add(computeUpRightNormal(adjLeftGrid));
		n.normalize();
		if( adjUpLeftGrid != null ) adjUpLeftGrid.normals[downRight].load(n);
		if( adjLeftGrid != null ) adjLeftGrid.normals[upRight].load(n);
		if( adjUpGrid != null ) adjUpGrid.normals[downLeft].load(n);
		grid.normals[upLeft].load(n);
		if( adjUpLeftTile != null ) adjUpLeftTile.needAlloc = true;

		// Down Left Corner
		n.set(0,0,0);
		n = n.add(computeDownLeftNormal(grid));
		n = n.add(computeUpLeftNormal(adjDownGrid));
		n = n.add(computeDownRightNormal(adjLeftGrid));
		n = n.add(computeUpRightNormal(adjDownLeftGrid));
		n.normalize();
		if( adjDownLeftGrid != null ) adjDownLeftGrid.normals[upRight].load(n);
		if( adjLeftGrid != null ) adjLeftGrid.normals[downRight].load(n);
		if( adjDownGrid != null ) adjDownGrid.normals[upLeft].load(n);
		grid.normals[downLeft].load(n);
		if( adjDownLeftTile != null ) adjDownLeftTile.needAlloc = true;

		// Down Right Corner
		n.set(0,0,0);
		n = n.add(computeDownLeftNormal(adjRightGrid));
		n = n.add(computeUpLeftNormal(adjDownRightGrid));
		n = n.add(computeDownRightNormal(grid));
		n = n.add(computeUpRightNormal(adjDownGrid));
		n.normalize();
		if( adjDownRightGrid != null ) adjDownRightGrid.normals[upLeft].load(n);
		if( adjRightGrid != null ) adjRightGrid.normals[downLeft].load(n);
		if( adjDownGrid != null ) adjDownGrid.normals[upRight].load(n);
		grid.normals[downRight].load(n);
		if( adjDownLeftTile != null ) adjDownLeftTile.needAlloc = true;
		
		needAlloc = true;
	}

	public function computeNormals() {
		if( grid != null )
			grid.addNormals();
	}

	public function computeTangents() {
		if( grid != null )
			grid.addTangents();
	}

	public function getHeight( u : Float, v : Float, ?fast = false ) : Float {
		var pixels = getHeightPixels();
		if( pixels == null ) return 0.0;
		if( !fast ) {
			inline function getPix(u, v) {
				return pixels.getPixelF(Std.int(hxd.Math.clamp(u, 0, pixels.width - 1)), Std.int(hxd.Math.clamp(v, 0, pixels.height - 1))).r;
			}
			var px = u * (pixels.width - 1) ;
            var py = v * (pixels.height - 1) ;
			var pxi = hxd.Math.floor(px);
            var pyi = hxd.Math.floor(py);
			var c00 = getPix(pxi, pyi);
			var c10 = getPix(pxi + 1, pyi);
			var c01 = getPix(pxi, pyi + 1);
			var c11 = getPix(pxi + 1, pyi + 1);
			var wx = px - pxi;
			var wy = py - pyi;
			var a = c00 * (1 - wx) + c10 * wx;
			var b = c01 * (1 - wx) + c11 * wx;
			return a * (1 - wy) + b * wy;

		}
		else{
			var x = hxd.Math.floor(u * (pixels.width - 1) + 0.5);
			var y = hxd.Math.floor(v * (pixels.height - 1) + 0.5);
			return pixels.getPixelF(x, y).r;
		}
	}

	var cachedBounds : h3d.col.Bounds;
	function computeBounds() {
		if( cachedBounds == null ) {
			if( heightMap != null ) {
				cachedBounds = new h3d.col.Bounds();
				cachedBounds.xMax = terrain.tileSize.x;
				cachedBounds.xMin = 0.0;
				cachedBounds.yMax = terrain.tileSize.y;
				cachedBounds.yMin = 0.0;
				for( u in 0 ... heightMap.width ) {
					for( v in 0 ... heightMap.height ) {
						var h = getHeight(u / heightMap.width, v / heightMap.height, true);
						if( cachedBounds.zMin > h ) cachedBounds.zMin = h;
						if( cachedBounds.zMax < h ) cachedBounds.zMax = h;
					}
				}
			}
			else if( bigPrim != null ) {
				cachedBounds = bigPrim.getBounds();
			}
			cachedBounds.transform(getAbsPos());
		}
	}

	public dynamic function beforeEmit() : Bool { return true; };
	override function emit( ctx:h3d.scene.RenderContext ) {
		if( !isReadyForDraw() ) return;
		computeBounds();
		insideFrustrum = cachedBounds != null ? ctx.camera.frustum.hasBounds(cachedBounds) : true;
		var b = beforeEmit();
		if( b && insideFrustrum )
			super.emit(ctx);
	}

	override function sync(ctx:h3d.scene.RenderContext) {

		shader.SHOW_GRID = #if editor terrain.showGrid #else false #end;
		shader.CHECKER = #if editor terrain.showChecker #else false #end;
		shader.COMPLEXITY = #if editor terrain.showComplexity #else false #end;
		shader.VERTEX_DISPLACEMENT = bigPrim == null;
		shader.SURFACE_COUNT = terrain.surfaceArray.surfaceCount;
		shader.PARALLAX = terrain.enableParallax && terrain.parallaxAmount != 0;

		shader.primSize.set(terrain.tileSize.x, terrain.tileSize.y);
		shader.cellSize.set(terrain.cellSize.x, terrain.cellSize.y);

		shader.albedoTextures = terrain.surfaceArray.albedo;
		shader.normalTextures = terrain.surfaceArray.normal;
		shader.pbrTextures = terrain.surfaceArray.pbr;
		shader.weightTextures = surfaceWeightArray;
		shader.heightMap = heightMap;
		shader.surfaceIndexMap = surfaceIndexMap;

		shader.surfaceParams = terrain.surfaceArray.params;
		shader.secondSurfaceParams = terrain.surfaceArray.secondParams;
		shader.tileIndex.set(tileX, tileY);
		shader.parallaxAmount = terrain.parallaxAmount;
		shader.minStep = terrain.parallaxMinStep;
		shader.maxStep = terrain.parallaxMaxStep;
		shader.heightBlendStrength = terrain.heightBlendStrength;
		shader.blendSharpness = terrain.blendSharpness;

		// OnContextLost support : re-create the bigPrim
		var needRealloc = false;
		if( bigPrim != null ) {
			for( b in @:privateAccess bigPrim.buffers ) {
				if( b.isDisposed() ) {
					needRealloc = true;
					break;
				}
			}
			if( needRealloc ) {
				createBigPrim(normalTangentBytes);
				cachedBounds = null;
			}
		}
	}

	function isReadyForDraw() {
		if( primitive == null )
			return false;

		if( bigPrim == null && (heightMap == null || heightMap.isDisposed()) )
			return false;

		if( !shader.CHECKER && (shader.weightTextures == null || shader.weightTextures.isDisposed()) )
			return false;

		if( !shader.CHECKER && !shader.COMPLEXITY ) {
			if( shader.albedoTextures == null || shader.albedoTextures.isDisposed() ) return false;
			if( shader.normalTextures == null || shader.normalTextures.isDisposed() ) return false;
			if( shader.pbrTextures == null || shader.pbrTextures.isDisposed() ) return false;
			if( shader.surfaceIndexMap == null || shader.surfaceIndexMap.isDisposed() ) return false;
		}

		return true;
	}
}
