package hrt.prefab.terrain;

class NormalBake extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var heightMap : Sampler2D;
		@param var heightMapSize : Vec2;

		function fragment() {
			var pixelSize = 1.0 / heightMapSize;
			var h = heightMap.get(calculatedUV).r;
			var h1 = heightMap.get(calculatedUV + vec2(0, pixelSize.y)).r;
			var h2 = heightMap.get(calculatedUV + vec2(pixelSize.x, 0)).r;
			var h3 = heightMap.get(calculatedUV + vec2(0, -pixelSize.y)).r;
			var h4 = heightMap.get(calculatedUV + vec2(-pixelSize.x, 0)).r;
			var v1 = vec3( 0, 1, h1 - h);
			var v2 = vec3( 1, 0, h2 - h);
			var v3 = vec3( 0, -1, h3 - h);
			var v4 = vec3( -1, 0, h4 - h);
			var n = (cross(v1, v2) + cross(v2, v3) + cross(v3, v4) + cross(v4, v1)) / -4;
			n = n.normalize();
			pixelColor.rgb = n * 0.5 + 0.5;
		}
	};
}

enum Direction {
	Up; Down; Left; Right; UpLeft; UpRight; DownLeft; DownRight;
}

@:access(hrt.prefab.terrain.TerrainMesh)
class Tile extends h3d.scene.Mesh {

	var shader : hrt.shader.Terrain;
	var terrain : TerrainMesh;

	// INDEXES
	public var tileX (default, null) : Int;
	public var tileY (default, null) : Int;

	// TEXTURE & PIXEL
	public var heightMap : h3d.mat.Texture;
	var heightMapPixels : hxd.Pixels;

	public var normalMap(default, null) : h3d.mat.Texture;
	var normalMapPixels : hxd.Pixels.Pixels;
	var needNormalBake = true;

	public var surfaceIndexMap : h3d.mat.Texture;
	public var surfaceWeights : Array<h3d.mat.Texture> = [];
	public var surfaceWeightArray (default, null) : h3d.mat.TextureArray;
	public var needNewPixelCapture = false;

	// PRIMITIVE
	var bigPrim : h3d.prim.BigPrimitive;
	public var insideFrustrum(default, null) = false;

	// Set by prefab loader for CPU access ingame
	public var packedWeightMapPixel : hxd.Pixels;
	public var indexMapPixels : hxd.Pixels;
	public var normalTangentBytes : haxe.io.Bytes;

	public function new( x : Int, y : Int, parent : TerrainMesh) {
		super(null, null, parent);
		terrain = parent;
		tileX = x;
		tileY = y;
		shader = new hrt.shader.Terrain();
		material.mainPass.addShader(shader);
		material.mainPass.culling = Back;
		material.mainPass.setPassName("terrain");
		material.mainPass.stencil = new h3d.mat.Stencil();
		material.mainPass.stencil.setFunc(Always, 0x01, 0xFF, 0xFF);
		material.mainPass.stencil.setOp(Keep, Keep, Replace);
		this.x = x * terrain.tileSize.x;
		this.y = y * terrain.tileSize.y;
		name = "tile_" + x + "_" + y;
	}

	override function onRemove() {
		super.onRemove();

		inline function disposeTex( t : h3d.mat.Texture ) { if( t != null ) { t.dispose();  t = null; } }
		inline function disposePixels( p : hxd.Pixels ) { if( p != null ) { p.dispose(); p = null; } }

		disposeTex(heightMap);
		disposeTex(normalMap);
		disposeTex(surfaceIndexMap);
		disposeTex(surfaceWeightArray);
		for( i in 0 ... surfaceWeights.length )
			disposeTex(surfaceWeights[i]);

		disposePixels(packedWeightMapPixel);
		disposePixels(indexMapPixels);
		disposePixels(heightMapPixels);

		normalTangentBytes = null;
		if( bigPrim != null ) bigPrim.dispose();
	}

	public inline function getHeightMapPixels() {
		if( (needNewPixelCapture || heightMapPixels == null) && heightMap != null )
			heightMapPixels = heightMap.capturePixels();
		needNewPixelCapture = false;
		return heightMapPixels;
	}

	public inline function getNormalMapPixels() {
		if( normalMapPixels == null && normalMap != null )
			normalMapPixels = normalMap.capturePixels();
		return normalMapPixels;
	}

	function bakeNormal() {
		if( heightMap == null )
			throw "Can't bake the normalMap of the tile if the heightMap is null.";
		var s = new NormalBake();
		s.heightMap = heightMap;
		s.heightMapSize.set(heightMap.width, heightMap.height);
		h3d.pass.ScreenFx.run(s, normalMap);
		needNormalBake = false;
		if( normalMapPixels != null ) {
			normalMapPixels.dispose();
			normalMapPixels = null;
		}
	}

	public function createBigPrim() {

		if( normalMapPixels == null || heightMapPixels == null )
			return;

		if( bigPrim != null )
			bigPrim.dispose();

		bigPrim = new h3d.prim.BigPrimitive(6, true);

		var cellCount = terrain.cellCount;
		var cellSize = terrain.cellSize;
		inline function addVertice(x : Int, y : Int) {
			// Pos
			bigPrim.addPoint(x * cellSize.x, y * cellSize.y, getHeight((x * cellSize.x) / terrain.tileSize.x, (y * cellSize.y) / terrain.tileSize.y, true)); // Use addPoint() instead of addVertexValue() for the bounds
			// Normal
			var n = h3d.Vector.fromColor(normalMapPixels.getPixel(x, y));
			n = n.add(new h3d.Vector(-0.5, -0.5, -0.5));
			n.scale3(2.0);
			bigPrim.addVertexValue(n.x);
			bigPrim.addVertexValue(n.y);
			bigPrim.addVertexValue(n.z);
		}

		bigPrim.begin(0,0);
		for( y in 0 ... cellCount.y + 1 ) {
			for( x in 0 ... cellCount.x + 1 ) {
				addVertice(x, y);
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
	}

	function refreshNormalMap() {
		if( normalMap == null || normalMap.width != terrain.heightMapResolution.x || normalMap.height != terrain.heightMapResolution.y ) {
			var oldNormalMap = normalMap;
			normalMap = new h3d.mat.Texture(terrain.heightMapResolution.x, terrain.heightMapResolution.y, [Target], RGBA);
			normalMap.setName("terrainNormalMap");
			normalMap.wrap = Clamp;
			normalMap.filter = Linear;
			normalMap.preventAutoDispose();
			normalMap.realloc = function() {
				if( normalMapPixels != null )
					normalMap.uploadPixels(normalMapPixels);
				else
					needNormalBake = true;
			}
			if( oldNormalMap != null )
				oldNormalMap.dispose();

			if( normalMapPixels != null && (normalMapPixels.width != normalMap.width || normalMapPixels.height != normalMap.height) ) {
				normalMapPixels.dispose();
				normalMapPixels = null;
			}
		}
	}

	function refreshHeightMap() {
		if( heightMap == null || heightMap.width != terrain.heightMapResolution.x || heightMap.height != terrain.heightMapResolution.y ) {
			var oldHeightMap = heightMap;
			heightMap = new h3d.mat.Texture(terrain.heightMapResolution.x, terrain.heightMapResolution.y, [Target], R32F);
			heightMap.setName("terrainHeightMap");
			heightMap.wrap = Clamp;
			heightMap.filter = Linear;
			heightMap.preventAutoDispose();
			needNewPixelCapture = true;

			heightMap.realloc = function() {
				if( heightMapPixels != null )
					heightMap.uploadPixels(heightMapPixels);
			}

			if( oldHeightMap != null ) {
				h3d.pass.Copy.run(oldHeightMap, heightMap);
				oldHeightMap.dispose();
			}

			if( heightMapPixels != null && (heightMapPixels.width != heightMap.width || heightMapPixels.height != heightMap.height) ) {
				heightMapPixels.dispose();
				heightMapPixels = null;
			}
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
				if( indexMapPixels != null )
					surfaceIndexMap.uploadPixels(indexMapPixels);
			}

			if( oldSurfaceIndexMap != null ) {
				h3d.pass.Copy.run(oldSurfaceIndexMap, surfaceIndexMap);
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
						h3d.pass.Copy.run(oldArray[i], surfaceWeights[i]);
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
		refreshNormalMap();
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
			if( surfaceWeights[i] != null ) h3d.pass.Copy.run(surfaceWeights[i], surfaceWeightArray, None, null, i);
	}

	public function getHeight( u : Float, v : Float, ?fast = false ) : Float {
		var pixels = heightMapPixels;
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
			var x = hxd.Math.floor(u * (pixels.width - 1));
			var y = hxd.Math.floor(v * (pixels.height - 1));
			return pixels.getPixelF(x, y).r;
		}
	}

	var cachedBounds : h3d.col.Bounds;
	function computeBounds() {

		if( bigPrim == null && heightMapPixels == null )
			return;

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
		}
		if( cachedBounds != null )
			cachedBounds.transform(getAbsPos());
	}

	inline public function getCachedBounds() : h3d.col.Bounds {
		if( cachedBounds == null )
			computeBounds();
		return cachedBounds;
	}

	public dynamic function beforeEmit() : Bool { return true; };
	override function emit( ctx:h3d.scene.RenderContext ) {
		if( !isReadyForDraw() )
			return;
		insideFrustrum = getCachedBounds() != null ? ctx.camera.frustum.hasBounds(getCachedBounds()) : false;
		insideFrustrum = true;
		var b = beforeEmit();
		if( b && insideFrustrum )
			super.emit(ctx);
	}

	override function sync(ctx:h3d.scene.RenderContext) {

		primitive = bigPrim == null ? terrain.primitive : bigPrim;

		// DEBUG
		shader.SHOW_GRID = #if editor terrain.showGrid #else false #end;
		shader.CHECKER = #if editor terrain.showChecker #else false #end;
		shader.COMPLEXITY = #if editor terrain.showComplexity #else false #end;

		// TILE INFO
		shader.VERTEX_DISPLACEMENT = bigPrim == null;
		shader.primSize.set(terrain.tileSize.x, terrain.tileSize.y);
		shader.cellSize.set(terrain.cellSize.x, terrain.cellSize.y);
		shader.tileIndex.set(tileX, tileY);

		// SURFACE
		if( terrain.surfaceArray != null ) {
			shader.SURFACE_COUNT = terrain.surfaceArray.surfaceCount;
			shader.albedoTextures = terrain.surfaceArray.albedo;
			shader.normalTextures = terrain.surfaceArray.normal;
			shader.pbrTextures = terrain.surfaceArray.pbr;
			shader.surfaceParams = terrain.surfaceArray.params;
			shader.secondSurfaceParams = terrain.surfaceArray.secondParams;
		}

		// BLEND PARAM
		shader.PARALLAX = terrain.enableParallax && terrain.parallaxAmount != 0;
		shader.parallaxAmount = terrain.parallaxAmount;
		shader.minStep = terrain.parallaxMinStep;
		shader.maxStep = terrain.parallaxMaxStep;
		shader.heightBlendStrength = terrain.heightBlendStrength;
		shader.blendSharpness = terrain.blendSharpness;

		// TILE TEXTURE
		shader.weightTextures = surfaceWeightArray;
		shader.heightMap = heightMap;
		shader.normalMap = normalMap;
		shader.surfaceIndexMap = surfaceIndexMap;


		if( bigPrim == null && needNormalBake && isReadyForDraw() )
			bakeNormal();

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
				createBigPrim();
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
