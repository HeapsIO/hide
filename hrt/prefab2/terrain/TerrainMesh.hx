package hrt.prefab2.terrain;

import h3d.mat.Texture;

@:access(hrt.prefab2.terrain.Tile)
class TerrainMesh extends h3d.scene.Object {

	var primitive : h3d.prim.BigPrimitive;

	// Resolution Vertexes/Pixels
	public var tileSize : h2d.col.Point;
	public var cellSize : h2d.col.Point;
	public var cellCount : h2d.col.IPoint;

	public var heightMapResolution : h2d.col.IPoint;
	public var weightMapResolution : h2d.col.IPoint;
	public var useBigPrim = false;

	// Shader Params
	#if editor
	public var showGrid : Bool;
	public var showChecker : Bool;
	public var showComplexity : Bool;
	#end
	public var enableParallax : Bool = true;
	public var parallaxAmount : Float;
	public var parallaxMinStep : Int;
	public var parallaxMaxStep : Int;
	public var heightBlendStrength : Float;
	public var blendSharpness : Float;

	// Data
	var tiles : Array<Tile> = [];
	var surfaces : Array<Surface> = [];
	var surfaceArray : Surface.SurfaceArray;

	public function new(?parent){
		super(parent);
	}

	override function onRemove() {
		super.onRemove();
		if( surfaceArray != null )
			surfaceArray.dispose();
	}

	public function getLocalHeight( x : Float, y : Float, fast = false) : Null<Float> {
		var xi = hxd.Math.floor(x/tileSize.x);
		var yi = hxd.Math.floor(y/tileSize.y);
		var t = getTile(xi, yi);
		if( t != null ) {
			return t.getHeight((x - xi * tileSize.x) / tileSize.x, (y - yi * tileSize.y) / tileSize.y, fast);
		}
		return null;
	}

	public function getHeight( x : Float, y : Float, fast = false) : Null<Float> {
		var t = getTileAtWorldPos(x, y);
		if( t != null ) {
			tmpPt.set(x, y);
			var pos = t.globalToLocal(tmpPt);
			return t.getHeight(pos.x / tileSize.x, pos.y / tileSize.y, fast);
		}
		return null;
	}

	public function getSurface( i : Int ) : Surface {
		if(i < surfaces.length)
				return surfaces[i];
		return null;
	}

	public function getSurfaceFromTex( albedo, ?normal, ?pbr ) : Surface {
		for( s in surfaces ) {
			var valid = false;
			valid = s.albedo.name == albedo;
			valid = valid && !( normal != null && s.normal.name != normal );
			valid = valid && !( pbr != null && s.pbr.name != pbr );
			if( valid ) return s;
		}
		return null;
	}

	public function addSurface( albedo, normal, pbr ) : Surface {
		surfaces.push(new Surface(albedo, normal, pbr));
		return surfaces[surfaces.length - 1];
	}

	public function addEmptySurface() : Surface {
		surfaces.push( new Surface() );
		return surfaces[surfaces.length - 1];
	}

	public function generateSurfaceArray() {
		if( surfaces.length == 0 ) return;
		var surfaceSize = 1;
		for( i in 0 ... surfaces.length )
			if( surfaces[i].albedo != null ) surfaceSize = hxd.Math.ceil(hxd.Math.max(surfaces[i].albedo.width, surfaceSize));

		if(surfaceArray != null) surfaceArray.dispose();
		surfaceArray = new Surface.SurfaceArray(surfaces.length, surfaceSize);
		for( i in 0 ... surfaces.length ) {
			if( surfaces[i].albedo != null ) h3d.pass.Copy.run(surfaces[i].albedo, surfaceArray.albedo, null, null, i);
			if( surfaces[i].normal != null ) h3d.pass.Copy.run(surfaces[i].normal, surfaceArray.normal, null, null, i);
			if( surfaces[i].pbr != null ) h3d.pass.Copy.run(surfaces[i].pbr, surfaceArray.pbr, null, null, i);
		}

		// OnContextLost support
		surfaceArray.albedo.realloc = function() {
			for( i in 0 ... surfaceArray.surfaceCount )
				h3d.pass.Copy.run(surfaces[i].albedo, surfaceArray.albedo, null, null, i);
		}
		surfaceArray.normal.realloc = function() {
			for( i in 0 ... surfaceArray.surfaceCount )
				h3d.pass.Copy.run(surfaces[i].normal, surfaceArray.normal, null, null, i);
		}
		surfaceArray.pbr.realloc = function() {
			for( i in 0 ... surfaceArray.surfaceCount )
				h3d.pass.Copy.run(surfaces[i].pbr, surfaceArray.pbr, null, null, i);
		}

		updateSurfaceParams();
		refreshAllTex();
	}

	public function updateSurfaceParams() {
		for( i in 0 ... surfaces.length ) {
			surfaceArray.params[i] = new h3d.Vector(surfaces[i].tilling, surfaces[i].offset.x, surfaces[i].offset.y, hxd.Math.degToRad(surfaces[i].angle));
			surfaceArray.secondParams[i] = new h3d.Vector(surfaces[i].minHeight, surfaces[i].maxHeight, 0, 0);
		}
	}

	function createBigPrimitive() {

		if( primitive != null )
			primitive.dispose();

		primitive = new h3d.prim.BigPrimitive(3, true);

		inline function addVertice(x : Float, y : Float) {
			primitive.addPoint(x, y, 0);
		}

		primitive.begin(0,0);
		for( y in 0 ... cellCount.y + 1 ) {
			for( x in 0 ... cellCount.x + 1 ) {
				addVertice(x * cellSize.x, y * cellSize.y);
			}
		}

		for( y in 0 ... cellCount.y ) {
			for( x in 0 ... cellCount.x ) {
				var i = x + y * (cellCount.x + 1);
				if( i % 2 == 0 ) {
					primitive.addIndex(i);
					primitive.addIndex(i + 1);
					primitive.addIndex(i + cellCount.x + 2);
					primitive.addIndex(i);
					primitive.addIndex(i + cellCount.x + 2);
					primitive.addIndex(i + cellCount.x + 1);
				}
				else {
					primitive.addIndex(i + cellCount.x + 1);
					primitive.addIndex(i);
					primitive.addIndex(i + 1);
					primitive.addIndex(i + 1);
					primitive.addIndex(i + cellCount.x + 2);
					primitive.addIndex(i + cellCount.x + 1);
				}
			}
		}
		primitive.flush();
	}

	public function refreshAllGrids() {
		createBigPrimitive();
	}

	public function refreshAllTex() {
		for( tile in tiles )
			tile.refreshTex();
	}

	public function refreshAll() {
		refreshAllGrids();
		refreshAllTex();
	}

	public function createTile(x : Int, y : Int, ?createTexture = true) : Tile {
		var tile = getTile(x,y);
		if(tile == null){
			tile = new Tile(x, y, this);
			if( createTexture ) tile.refreshTex();
			tiles.push(tile);
		}
		return tile;
	}

	public function addTile( tile : Tile, ?replace = false ) {
		for( t in tiles ) {
			if( tile == t ) return;
			if( tile.tileX == t.tileX && tile.tileY == t.tileY ) {
				if( replace ) {
					removeTile(t);
					break;
				}else
					return;
			}
		}
		tile.parent = this;
		tiles.push(tile);
		addChild(tile);
	}

	public function removeTileAt( x : Int, y : Int ) : Bool {
		var t = getTile(x,y);
		if( t == null ) {
			removeTile(t);
			return true;
		}
		return false;
	}

	public function removeTile( t : Tile ) : Bool {
		if( t == null ) return false;
		var r = tiles.remove(t);
		if( r ) t.remove();
		return r;
	}

	public function getTileIndex( t : Tile ) : Int {
		for( i in 0 ... tiles.length )
			if( t == tiles[i] ) return i;
		return -1;
	}

	public function getTile( x : Int, y : Int ) : Tile {
		var result : Tile = null;
		for( tile in tiles )
			if( tile.tileX == x && tile.tileY == y ) result = tile;
		return result;
	}

	public function getTileAtWorldPos( x : Float, y : Float ) : Tile {
		var pos = toLocalPos(x, y);
		var result : Tile = null;
		var tileX = Math.floor(pos.x / tileSize.x);
		var tileY = Math.floor(pos.y / tileSize.y);
		for( tile in tiles )
			if( tile.tileX == tileX && tile.tileY == tileY ) result = tile;
		return result;
	}

	public function createTileAtWorldPos( x : Float, y : Float ) : Tile {
		var pos = toLocalPos(x, y);
		var tileX = Math.floor(pos.x / tileSize.x);
		var tileY = Math.floor(pos.y / tileSize.y);
		var result = getTile(tileX, tileY);
		return result == null ? createTile(tileX, tileY) : result;
	}

	public function getTiles( x : Float, y : Float, range : Float, ?create = false ) : Array<Tile> {
		var pos = toLocalPos(x, y);
		if( create != null && create ) {
			var maxTileX = Math.floor((pos.x + range)/ tileSize.x);
			var minTileX = Math.floor((pos.x - range)/ tileSize.x);
			var maxTileY = Math.floor((pos.y + range)/ tileSize.y);
			var minTileY = Math.floor((pos.y - range)/ tileSize.y);
			for( x in minTileX ... maxTileX + 1) {
				for( y in minTileY...maxTileY + 1) {
					var t = createTile(x, y);
					#if editor
					t.material.mainPass.stencil = new h3d.mat.Stencil();
					t.material.mainPass.stencil.setFunc(Always, 0x01, 0x01, 0x01);
					t.material.mainPass.stencil.setOp(Keep, Keep, Replace);
					#end
				}
			}
		}
		var result : Array<Tile> = [];
		for( tile in tiles)
			if( Math.abs(pos.x - (tile.tileX * tileSize.x + tileSize.x * 0.5)) <= range + (tileSize.x * 0.5)
			&& Math.abs(pos.y - (tile.tileY * tileSize.y + tileSize.y * 0.5)) <= range + (tileSize.y * 0.5) )
				result.push(tile);
		return result;
	}

	static var tmpPt = new h3d.col.Point();
	inline function toLocalPos( x : Float, y : Float ) {
		tmpPt.set(x, y);
		globalToLocal(tmpPt);
		return tmpPt;
	}
}


