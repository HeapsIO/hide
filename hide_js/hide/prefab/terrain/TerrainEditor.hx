package hide.prefab.terrain;
using Lambda;
import hxd.Pixels;
import hrt.prefab.terrain.Tile;
import hxd.Key as K;

enum RenderMode {
	PBR;
	ShaderComplexity;
	Checker;
}

class TerrainRevertData {
	public var surfaceIndex : Int;
	public var surface : hrt.prefab.terrain.Surface;
	public function new(){

	}
}

class TileRevertData {
	public var x : Int;
	public var y : Int;
	public var prevHeightMapPixels : hxd.Pixels;
	public var nextHeightMapPixels : hxd.Pixels;
	public var prevWeightMapPixels : Array<hxd.Pixels> = [];
	public var nextWeightMapPixels : Array<hxd.Pixels> = [];
	public var prevSurfaceIndexMapPixels : hxd.Pixels;
	public var nextSurfaceIndexMapPixels : hxd.Pixels;
	public function new(x, y){
		this.x = x;
		this.y = y;
	}
}

@:access(hrt.prefab.terrain.TerrainMesh)
@:access(hrt.prefab.terrain.Terrain)
@:access(hrt.prefab.terrain.Tile)
class TerrainEditor {

	public var currentBrush = new Brush();
	public var currentSurface : hrt.prefab.terrain.Surface;
	public var textureType = ["_Albedo", "_Normal", "_MetallicGlossAO"];
	public var autoCreateTile = false;
	public var allowDisconnectedTiles = false;

	public var editContext : hide.prefab.EditContext;

	// Debug
	var renderMode : RenderMode = PBR;
	// Edition
	var brushPreview : hide.prefab.terrain.Brush.BrushPreview;
	var interactive : h2d.Interactive;
	var remainingDist = 0.0;
	var lastPos : h3d.col.Point;
	var lastMousePos : h2d.col.Point;
	var lastBrushSize : Float;
	var heightStrokeBufferArray : hide.prefab.terrain.StrokeBuffer.StrokeBufferArray;
	var weightStrokeBufferArray : hide.prefab.terrain.StrokeBuffer.StrokeBufferArray;
	// Shader for edition
	var copyPass = new h3d.pass.Copy();
	var normalizeWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.NormalizeWeight());
	var clampWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.ClampWeight());
	var generateIndex = new h3d.pass.ScreenFx(new hide.prefab.terrain.GenerateIndex());
	var swapIndex = new h3d.pass.ScreenFx(new hide.prefab.terrain.SwapIndex());
	var setHeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.SetHeight());
	var smoothHeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.SmoothHeight());
	// Revert
	var terrainPrefab : hrt.prefab.terrain.Terrain;
	var undo : hide.ui.UndoHistory;
	var tileTrashBin : Array<TileRevertData> = [];
	var paintRevertDatas : Array<TileRevertData> = [];
	// Render UV offscreen
	var uvTexPixels : hxd.Pixels;
	var uvTex : h3d.mat.Texture;
	var uvTexRes = 0.5;
	var customScene = new h3d.scene.Scene(false, false);
	var customRenderer = new hide.prefab.terrain.CustomRenderer("terrainUV");

	public function new( terrainPrefab : hrt.prefab.terrain.Terrain, undo : hide.ui.UndoHistory ) {
		this.terrainPrefab = terrainPrefab;
		this.undo = undo;
		renderMode = terrainPrefab.showChecker ? Checker : PBR;
		autoCreateTile = terrainPrefab.autoCreateTile;
		allowDisconnectedTiles = terrainPrefab.allowDisconnectedTiles;

		brushPreview = new hide.prefab.terrain.Brush.BrushPreview(terrainPrefab.terrain);

		heightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(R32F,new h2d.col.IPoint(terrainPrefab.terrain.heightMapResolution.x, terrainPrefab.terrain.heightMapResolution.y));
		weightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(R8, terrainPrefab.terrain.weightMapResolution);
		customScene.renderer = customRenderer;
		#if debug
		customScene.checkPasses = false;
		#end
	}

	public function dispose() {
		if(uvTex != null) uvTex.dispose();
		heightStrokeBufferArray.dispose();
		weightStrokeBufferArray.dispose();
		brushPreview.remove();
		if( interactive != null ) interactive.remove();
	}

	public function update( ?propName : String ) {
		if( propName == "editor.currentSurface.tilling"
		|| propName == "editor.currentSurface.offset.x"
		|| propName == "editor.currentSurface.offset.y"
		|| propName == "editor.currentSurface.angle"
		|| propName == "editor.currentSurface.minHeight"
		|| propName == "editor.currentSurface.maxHeight"
		|| propName == "editor.currentSurface.parallaxAmount" )
			terrainPrefab.terrain.updateSurfaceParams();

		autoCreateTile = terrainPrefab.autoCreateTile;
		allowDisconnectedTiles = terrainPrefab.allowDisconnectedTiles;
		brushPreview.opacity = terrainPrefab.brushOpacity;

		if( propName == "editor.renderMode" ) updateRender();
	}

	public function refresh() {
		heightStrokeBufferArray.refresh(new h2d.col.IPoint(terrainPrefab.terrain.heightMapResolution.x + 1, terrainPrefab.terrain.heightMapResolution.y + 1));
		weightStrokeBufferArray.refresh(terrainPrefab.terrain.weightMapResolution);
	}

	function updateRender() {
		for( tile in terrainPrefab.terrain.tiles )
			tile.material.removePass(tile.material.getPass("overlay"));
		terrainPrefab.terrain.showChecker = false;
		terrainPrefab.terrain.showComplexity = false;
		terrainPrefab.showChecker = false;
		switch( renderMode ) {
			case PBR :
			case ShaderComplexity : terrainPrefab.terrain.showComplexity = true;
			case Checker :
				terrainPrefab.terrain.showChecker = true;
				terrainPrefab.showChecker = true;
		}
	}

	function renderTerrainUV() {
		if( customScene == null ) return;
		if( terrainPrefab == null || terrainPrefab.local3d == null || terrainPrefab.local3d.getScene() == null ) return;
		var engine = h3d.Engine.getCurrent();
		var mainScene = @:privateAccess terrainPrefab.local3d.getScene();

		if( uvTex == null || uvTex.width != Std.int(h3d.Engine.getCurrent().width * uvTexRes) || uvTex.height != Std.int(h3d.Engine.getCurrent().height * uvTexRes) ) {
			if(uvTex != null) {
				uvTex.depthBuffer.dispose();
				uvTex.dispose();
			}
			uvTex = new h3d.mat.Texture( Std.int(h3d.Engine.getCurrent().width * uvTexRes),  Std.int(h3d.Engine.getCurrent().height * uvTexRes), [Target], RGBA32F);
			uvTex.depthBuffer = new h3d.mat.Texture(uvTex.width, uvTex.height, Depth24Stencil8);
		}

		var prevParent = terrainPrefab.terrain.parent;
		@:privateAccess {
			customScene.children = [terrainPrefab.terrain]; // Prevent OnRemove() call
			terrainPrefab.terrain.parent = customScene;
		}

		customScene.camera = mainScene.camera;
		brushPreview.reset();

		var tiles = terrainPrefab.terrain.tiles;
		for( i in 0 ... tiles.length ) {
			var tile = tiles[i];
			var p = new h3d.mat.Pass("terrainUV");
			p.addShader(new h3d.shader.BaseMesh());
			p.depthTest = Less;
			p.culling = None;
			p.depthWrite = true;
			tile.material.addPass(p);
			var s = new hide.prefab.terrain.CustomUV();
			s.primSize.set(terrainPrefab.terrain.tileSize.x, terrainPrefab.terrain.tileSize.y);
			s.heightMapSize.set(terrainPrefab.terrain.heightMapResolution.x, terrainPrefab.terrain.heightMapResolution.y);
			s.heightMap = tile.heightMap;
			s.tileIndex = i;
			p.addShader(s);
		}

		engine.begin();
		engine.pushTarget(uvTex);
		engine.clear(0xffffff,1,0);
		engine.clearF(new h3d.Vector4(-1, -1, -1, -1),1,0);
		customScene.render(engine);
		engine.popTarget();

		for( tile in tiles )
			tile.material.removePass(tile.material.getPass("terrainUV"));

		@:privateAccess {
			customScene.children = [];
			terrainPrefab.terrain.parent = prevParent;
		}
		customScene.camera = null;

		uvTexPixels = uvTex.capturePixels();
	}

	function checkTrashBin() {
		if( tileTrashBin.length > 0 ) {
			var tileTrashBinTmp = tileTrashBin.copy();
			tileTrashBin = [];
			undo.change(Custom(function(undo) {
				for( t in tileTrashBinTmp ) {
					if( undo ) {
						var tile = terrainPrefab.terrain.createTile(t.x, t.y);
						tile.material.mainPass.stencil = new h3d.mat.Stencil();
						tile.material.mainPass.stencil.setFunc(Always, 0x01, 0x01, 0x01);
						tile.material.mainPass.stencil.setOp(Keep, Keep, Replace);
						tile.refreshHeightMap();
						tile.refreshNormalMap();
						tile.refreshIndexMap();
						tile.refreshSurfaceWeightArray();
						tile.heightMap.uploadPixels(t.prevHeightMapPixels);
						tile.surfaceIndexMap.uploadPixels(t.prevSurfaceIndexMapPixels);
						for( i in 0 ... t.prevWeightMapPixels.length )
							tile.surfaceWeights[i].uploadPixels(t.prevWeightMapPixels[i]);
						tile.generateWeightTextureArray();
					}
					else
						terrainPrefab.terrain.removeTileAt(t.x, t.y);
				}
			}));
			tileTrashBin = [];
		}
	}

	function blendEdges( modifiedTile : Array<Tile> ) {

		// Adjust the edge for each modified tiles and their neighbors
		var tiles : Array<Tile> = [];
		for( t in modifiedTile ) {
			for( i in -1 ... 2 ) {
				for( j in - 1 ... 2 ) {
					var adj = t.terrain.getTile(t.tileX + i, t.tileY + j);
					if( adj != null && tiles.indexOf(adj) == -1 )
						tiles.push(adj);
				}
			}
		}

		// Adjust the height to avoid seams
		for( t in tiles ) {
			var pixels = t.getHeightMapPixels();
			if( pixels == null )
				throw("Try to blend the edges of a null heightmap.");
			var adjTileX = t.terrain.getTile(t.tileX + 1, t.tileY);
			var adjHeightMapX = adjTileX != null ? adjTileX.heightMap : null;
			if( adjHeightMapX != null ) {
				var adjpixels = adjTileX.getHeightMapPixels();
				for( i in 0 ... t.heightMap.height ) {
					pixels.setPixelF(t.heightMap.width - 1, i, adjpixels.getPixelF(0,i) );
				}
			}

			var adjTileY = t.terrain.getTile(t.tileX, t.tileY + 1);
			var adjHeightMapY = adjTileY != null ? adjTileY.heightMap : null;
			if( adjHeightMapY != null ) {
				var adjpixels = adjTileY.getHeightMapPixels();
				for( i in 0 ... t.heightMap.width ) {
					pixels.setPixelF(i, t.heightMap.height - 1, adjpixels.getPixelF(i,0) );
				}
			}

			var adjTileXY = t.terrain.getTile(t.tileX + 1, t.tileY + 1);
			var adjHeightMapXY = adjTileXY != null ? adjTileXY.heightMap : null;
			if( adjHeightMapXY != null ) {
				var adjpixels = adjTileXY.getHeightMapPixels();
				pixels.setPixelF(t.heightMap.width - 1, t.heightMap.height - 1, adjpixels.getPixelF(0,0));
			}

			t.heightMapPixels = pixels;
			t.heightMap.uploadPixels(pixels);
			t.needNewPixelCapture = false;
		}

		// Compute the normal for each tile, but there's seam on the edge
		for( t in tiles )  {
			t.bakeNormal();
			t.normalMapPixels = t.normalMap.capturePixels();
		}

		// Compute the average normal on edge
		for( t in tiles ) {

			var pixelsAfterBlend = t.normalMapPixels;
			var left = t.terrain.getTile(t.tileX - 1, t.tileY);
			var right = t.terrain.getTile(t.tileX + 1, t.tileY);
			var up = t.terrain.getTile(t.tileX, t.tileY - 1);
			var down = t.terrain.getTile(t.tileX, t.tileY + 1);
			var upRight = t.terrain.getTile(t.tileX + 1, t.tileY - 1);
			var upLeft = t.terrain.getTile(t.tileX - 1, t.tileY - 1);
			var downRight = t.terrain.getTile(t.tileX + 1, t.tileY + 1);
			var downLeft = t.terrain.getTile(t.tileX - 1, t.tileY + 1);
			var width = pixelsAfterBlend.width - 1;
			var height = pixelsAfterBlend.height - 1;

			// Return the normal of tile t at (x,y) without any blend
			function getNormalFromHeightMap(t : Tile, x : Int, y : Int ) {
				var h = t.heightMapPixels.getPixelF(x, y).x;
				var h1 = y + 1 >= t.heightMapPixels.height ? h : t.heightMapPixels.getPixelF(x, y + 1).x;
				var h2 = x + 1 >= t.heightMapPixels.width ? h : t.heightMapPixels.getPixelF(x + 1, y).x;
				var h3 = y - 1 < 0 ? h : t.heightMapPixels.getPixelF(x, y - 1).x;
				var h4 = x - 1 < 0 ? h : t.heightMapPixels.getPixelF(x - 1, y).x;
				var v1 = new h3d.Vector(0, 1, h1 - h);
				var v2 = new h3d.Vector(1, 0, h2 - h);
				var v3 = new h3d.Vector(0, -1, h3 - h);
				var v4 = new h3d.Vector(-1, 0, h4 - h);
				var n = v1.cross(v2).add(v2.cross(v3).add(v3.cross(v4).add(v4.cross(v1))));
				n.scale(-1.0);
				n.normalize();
				return n;
			}

			inline function packNormal( n : h3d.Vector ) {
				n.scale(0.5);
				return n.add(new h3d.Vector(0.5, 0.5, 0.5)).toColor();
			}

			inline function unpackNormal( n : Int ) {
				var n = h3d.Vector.fromColor(n);
				n = n.add(new h3d.Vector(-0.5, -0.5, -0.5));
				n.scale(2.0);
				return n;
			}

			for( i in 1 ... pixelsAfterBlend.width - 1 ) {
				if( up != null ) {
					var n = unpackNormal(pixelsAfterBlend.getPixel(i, 0)).add(getNormalFromHeightMap(up, i, height));
					n.normalize();
					pixelsAfterBlend.setPixel(i, 0, packNormal(n));
				}
				if( down != null ) {
					var n = unpackNormal(pixelsAfterBlend.getPixel(i, height)).add(getNormalFromHeightMap(down, i, 0));
					n.normalize();
					pixelsAfterBlend.setPixel(i, height, packNormal(n));
				}
			}
			for( i in 1 ... pixelsAfterBlend.height - 1 ) {
				if( left != null ) {
					var n = unpackNormal(pixelsAfterBlend.getPixel(0, i)).add(getNormalFromHeightMap(left, width, i));
					n.normalize();
					pixelsAfterBlend.setPixel(0, i, packNormal(n));
				}
				if( right != null ) {
					var n = unpackNormal(pixelsAfterBlend.getPixel(width, i)).add(getNormalFromHeightMap(right, 0, i));
					n.normalize();
					pixelsAfterBlend.setPixel(width, i, packNormal(n));
				}
			}

			var n = unpackNormal(pixelsAfterBlend.getPixel(0, 0));
			if( up != null ) n = n.add(getNormalFromHeightMap(up, 0, height));
			if( left != null ) n = n.add(getNormalFromHeightMap(left, width, 0));
			if( upLeft != null ) n = n.add(getNormalFromHeightMap(upLeft, width, height));
			n.normalize();
			pixelsAfterBlend.setPixel(0, 0, packNormal(n));

			var n = unpackNormal(pixelsAfterBlend.getPixel(width, 0));
			if( up != null ) n = n.add(getNormalFromHeightMap(up, width, height));
			if( right != null ) n = n.add(getNormalFromHeightMap(right, 0, 0));
			if( upRight != null ) n = n.add(getNormalFromHeightMap(upRight, 0, height));
			n.normalize();
			pixelsAfterBlend.setPixel(width, 0, packNormal(n));

			var n = unpackNormal(pixelsAfterBlend.getPixel(0, height));
			if( down != null ) n = n.add(getNormalFromHeightMap(down, 0, 0));
			if( left != null ) n = n.add(getNormalFromHeightMap(left, width, height));
			if( downLeft != null ) n = n.add(getNormalFromHeightMap(downLeft, width, 0));
			n.normalize();
			pixelsAfterBlend.setPixel(0, height, packNormal(n));

			var n = unpackNormal(pixelsAfterBlend.getPixel(width, height));
			if( down != null ) n = n.add(getNormalFromHeightMap(down, width, 0));
			if( right != null ) n = n.add(getNormalFromHeightMap(right, 0, height));
			if( downRight != null ) n = n.add(getNormalFromHeightMap(downRight, 0, 0));
			n.normalize();
			pixelsAfterBlend.setPixel(width, height, packNormal(n));

			t.normalMap.uploadPixels(pixelsAfterBlend);
			t.needNormalBake = false;
		}
	}

	function resetStrokeBuffers() {
		heightStrokeBufferArray.reset();
		weightStrokeBufferArray.reset();
	}

	function applyStrokeBuffers() {

		var revertDatas = new Array<TileRevertData>();

		for( strokeBuffer in heightStrokeBufferArray.strokeBuffers ) {
			if( strokeBuffer.used == true ) {
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.heightMap;
				tile.heightMap = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;
				var revert = new TileRevertData(strokeBuffer.x, strokeBuffer.y);
				revert.prevHeightMapPixels = tile.heightMapPixels;

				switch( currentBrush.brushMode.mode ) {
					case AddSub :
						copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.subAction ? Sub : Add);
					case Set :
						copyPass.apply(tile.heightMap, strokeBuffer.tempTex);
						setHeight.shader.prevHeight = strokeBuffer.tempTex;
						setHeight.shader.targetHeight = currentBrush.brushMode.setHeightValue;
						setHeight.shader.strengthTex = strokeBuffer.tex;
						h3d.Engine.getCurrent().pushTarget(tile.heightMap);
						setHeight.render();
					case Smooth :
						copyPass.apply(tile.heightMap, strokeBuffer.tempTex);
						smoothHeight.shader.prevHeight = strokeBuffer.tempTex;
						smoothHeight.shader.prevHeightResolution = new h3d.Vector(strokeBuffer.tempTex.width, strokeBuffer.tempTex.height);
						smoothHeight.shader.range = 4;
						smoothHeight.shader.strengthTex = strokeBuffer.tex;
						h3d.Engine.getCurrent().pushTarget(tile.heightMap);
						smoothHeight.render();
					default:
				}
				revertDatas.push(revert);
				tile.heightMapPixels = tile.heightMap.capturePixels();
				revert.nextHeightMapPixels = tile.heightMapPixels;
				tile.cachedBounds = null;
			}
		}
		var tiles = [ for( sb in heightStrokeBufferArray.strokeBuffers ) { if( sb.used ) terrainPrefab.terrain.getTile(sb.x, sb.y); }];
		blendEdges(tiles);

		if( revertDatas.length > 0 ) {
			undo.change(Custom(function(undo) {
				for( revertData in revertDatas ) {
					var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
					if( tile == null ) continue;
					tile.heightMap.uploadPixels(undo ? revertData.prevHeightMapPixels : revertData.nextHeightMapPixels);
					tile.heightMapPixels = undo ? revertData.prevHeightMapPixels : revertData.nextHeightMapPixels;
				}
				var tiles = [ for( rd in revertDatas ) { terrainPrefab.terrain.getTile(rd.x, rd.y); }];
				blendEdges(tiles);
			}));
		}

		for( strokeBuffer in weightStrokeBufferArray.strokeBuffers ) {
			if( strokeBuffer.used == true ) {
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;

				copyPass.apply(strokeBuffer.tex, tile.surfaceWeights[currentBrush.index], currentBrush.brushMode.subAction ? Sub : Add);
				tile.generateWeightTextureArray();

				clampWeight.shader.weightTextures = tile.surfaceWeightArray;
				clampWeight.shader.weightCount = tile.surfaceWeights.length;
				clampWeight.shader.baseTexIndex = currentBrush.index;
				for( i in 0 ... tile.surfaceWeights.length ) {
					if( i == currentBrush.index ) continue;
					clampWeight.shader.curTexIndex = i;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
					clampWeight.render();
				}
				tile.generateWeightTextureArray();

				normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
				normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
				normalizeWeight.shader.baseTexIndex = currentBrush.index;
				for( i in 0 ... tile.surfaceWeights.length ) {
					normalizeWeight.shader.curTexIndex = i;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
					normalizeWeight.render();
				}
				tile.generateWeightTextureArray();

				var revert : TileRevertData = null;
				for( r in paintRevertDatas )
					if( r.x == strokeBuffer.x && r.y == strokeBuffer.y ) {
						revert = r;
						break;
					}
				if( revert != null )
					for( w in tile.surfaceWeights )
						revert.nextWeightMapPixels.push(w.capturePixels());

				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
		}

		if( paintRevertDatas.length > 0 ) {
			var paintRevertdataTmp = paintRevertDatas.copy();
			paintRevertDatas = [];
			undo.change(Custom(function(undo) {
				for( revertData in paintRevertdataTmp ) {
					var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
					if (tile == null ) continue;
					for (i in 0 ... tile.surfaceWeights.length )
						tile.surfaceWeights[i].uploadPixels(undo ? revertData.prevWeightMapPixels[i] : revertData.nextWeightMapPixels[i]);
					tile.generateWeightTextureArray();
					generateIndex.shader.weightTextures = tile.surfaceWeightArray;
					generateIndex.shader.weightCount = tile.surfaceWeights.length;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
					generateIndex.render();
				}
			}));
		}
	}

	function previewStrokeBuffers() {
		for( strokeBuffer in heightStrokeBufferArray.strokeBuffers ) {
			if( strokeBuffer.used == true ) {
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				switch( currentBrush.brushMode.mode ) {
					case AddSub :
						copyPass.apply(strokeBuffer.prevTex, tile.heightMap);
						copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.subAction ? Sub : Add);
					case Set :
						setHeight.shader.prevHeight = strokeBuffer.prevTex;
						setHeight.shader.targetHeight = currentBrush.brushMode.setHeightValue;
						setHeight.shader.strengthTex = strokeBuffer.tex;
						h3d.Engine.getCurrent().pushTarget(tile.heightMap);
						setHeight.render();
					case Smooth :
						smoothHeight.shader.prevHeight = strokeBuffer.prevTex;
						smoothHeight.shader.prevHeightResolution = new h3d.Vector(strokeBuffer.tempTex.width, strokeBuffer.tempTex.height);
						smoothHeight.shader.range = 4;
						smoothHeight.shader.strengthTex = strokeBuffer.tex;
						h3d.Engine.getCurrent().pushTarget(tile.heightMap);
						smoothHeight.render();
					default:
				}
			}
		}

		for( strokeBuffer in weightStrokeBufferArray.strokeBuffers ) {
			if( strokeBuffer.used == true ) {
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				copyPass.apply(strokeBuffer.prevTex, strokeBuffer.tempTex);
				copyPass.apply(strokeBuffer.tex, strokeBuffer.tempTex, currentBrush.brushMode.subAction ? Sub : Add);
				tile.generateWeightTextureArray();

				var engine = h3d.Engine.getCurrent();
				clampWeight.shader.weightTextures = tile.surfaceWeightArray;
				clampWeight.shader.weightCount = tile.surfaceWeights.length;
				clampWeight.shader.baseTexIndex = currentBrush.index;
				for( i in 0 ... tile.surfaceWeights.length) {
					if( i == currentBrush.index ) continue;
					clampWeight.shader.curTexIndex = i;
					engine.pushTarget(tile.surfaceWeights[i]);
					clampWeight.render();
				}
				tile.generateWeightTextureArray();

				normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
				normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
				normalizeWeight.shader.baseTexIndex = currentBrush.index;
				for( i in 0 ... tile.surfaceWeights.length ) {
					normalizeWeight.shader.curTexIndex = i;
					engine.pushTarget(tile.surfaceWeights[i]);
					normalizeWeight.render();
				}
				tile.generateWeightTextureArray();

				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				engine.pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
		}
	}

	function projectToGround( ray: h3d.col.Ray ) {
		var minDist = -1.;
		var normal = terrainPrefab.terrain.getAbsPos().up();
		var plane = h3d.col.Plane.fromNormalPoint(normal.toPoint(), new h3d.col.Point(terrainPrefab.terrain.getAbsPos().tx, terrainPrefab.terrain.getAbsPos().ty, terrainPrefab.terrain.getAbsPos().tz));
		var pt = ray.intersect(plane);
		if(pt != null) { minDist = pt.sub(ray.getPos()).length();}
		return minDist;
	}

	function screenToWorld( u : Float, v : Float) {
        if( terrainPrefab == null || terrainPrefab.local3d == null || terrainPrefab.local3d.getScene() == null ) return new h3d.col.Point();
		var camera = @:privateAccess terrainPrefab.local3d.getScene().camera;
		var ray = camera.rayFromScreen(u, v);
		var dist = projectToGround(ray);
		return dist >= 0 ? ray.getPoint(dist) : new h3d.col.Point();
	}

	function worldToScreen( wx: Float, wy: Float, wz: Float) {
		if( terrainPrefab == null || terrainPrefab.local3d == null || terrainPrefab.local3d.getScene() == null) return new h2d.col.Point();
		var camera = @:privateAccess terrainPrefab.local3d.getScene().camera;
		var pt = camera.project(wx, wy, wz, h3d.Engine.getCurrent().width, h3d.Engine.getCurrent().height);
		return new h2d.col.Point(hxd.Math.abs(pt.x), hxd.Math.abs(pt.y));
	}

	function getBrushPlanePos( mouseX : Float, mouseY : Float) {
		var worldPos = screenToWorld(mouseX, mouseY);
		if( currentBrush.brushMode.snapToGrid ) {
			var localPos = terrainPrefab.terrain.globalToLocal(worldPos.clone());
			localPos.x = hxd.Math.round(localPos.x / terrainPrefab.terrain.cellSize.x) * terrainPrefab.terrain.cellSize.x;
			localPos.y = hxd.Math.round(localPos.y / terrainPrefab.terrain.cellSize.y) * terrainPrefab.terrain.cellSize.y;
			localPos.z = localPos.z;
			worldPos = terrainPrefab.terrain.globalToLocal(localPos.clone());
		}
		return worldPos;
	}

	function getBrushWorldPosFromTex( worldPos : h3d.col.Point) : h3d.col.Point {
		if(currentBrush.brushMode.snapToGrid) return worldPos;
		var screenPos = worldToScreen(worldPos.x, worldPos.y, worldPos.z);
		var brushWorldPos = worldPos.clone();
		var fetchPos = new h2d.col.Point(hxd.Math.floor(screenPos.x * uvTexRes), hxd.Math.floor(screenPos.y * uvTexRes));
		fetchPos.x = hxd.Math.clamp(fetchPos.x, 0, uvTexPixels.width - 1);
		fetchPos.y = hxd.Math.clamp(fetchPos.y, 0, uvTexPixels.height - 1);
		var pixel = uvTexPixels.getPixelF( Std.int(fetchPos.x), Std.int(fetchPos.y));
		var tiles = terrainPrefab.terrain.tiles;
		for( i in 0 ... tiles.length )
			if( hxd.Math.ceil(pixel.z) == i )
				brushWorldPos = tiles[i].localToGlobal(new h3d.col.Point(pixel.x * terrainPrefab.tileSizeX, pixel.y * terrainPrefab.tileSizeY, 0));
		return brushWorldPos;
	}

	function drawBrushPreview( worldPos : h3d.col.Point) {
		if(terrainPrefab == null || terrainPrefab.local3d == null || terrainPrefab.local3d.getScene() == null) return;
		brushPreview.reset();
		if( currentBrush.brushMode.mode == Delete || currentBrush.bitmap == null ) return;
		var brushWorldPos = uvTexPixels == null ? worldPos : getBrushWorldPosFromTex(worldPos);
		brushPreview.previewAt(currentBrush, brushWorldPos);
	}

	function applyBrush( pos : h3d.col.Point) {
		switch ( currentBrush.brushMode.mode ) {
			case Paint: drawSurface(pos);
			case AddSub: drawHeight(pos);
			case Smooth: drawHeight(pos);
			case Set: drawHeight(pos);
			case Delete: deleteTile(pos);
			default:
		}
		terrainPrefab.modified = true;
	}

	function useBrush( from : h3d.col.Point, to : h3d.col.Point) {
		var dist = (to.sub(from)).length();
		if( currentBrush.firstClick ) {
			if( currentBrush.brushMode.mode == Set ) {
				if( currentBrush.brushMode.subAction )
					currentBrush.brushMode.setHeightValue = terrainPrefab.terrain.getHeight(from.x, from.y);
				else
					currentBrush.brushMode.setHeightValue = currentBrush.strength;
			}
			applyBrush(from);
			previewStrokeBuffers();
			return;
		}

		if( currentBrush == null || currentBrush.step <= 0 ) return;

		var dist = (to.sub(from)).length();
		if( dist + remainingDist >= currentBrush.step ) {
			var dir = to.sub(from);
			dir.normalize();
			var pos = from.clone();
			var step = dir.clone();
			step.scale(currentBrush.step);
			while( dist + remainingDist >= currentBrush.step ) {
				if( remainingDist > 0 ) {
					var firstStep = dir.clone();
					firstStep.scale(currentBrush.step - remainingDist);
					pos = pos.add(firstStep);
				}else
					pos = pos.add(step);
				applyBrush(pos);
				dist -= currentBrush.step - remainingDist;
				remainingDist = 0;
			}
			remainingDist = dist;
			previewStrokeBuffers();
		}else
			remainingDist += dist;
	}

	public function deleteTile( pos : h3d.col.Point) {
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos);
		if( brushWorldPos == null ) return;
		var tile = terrainPrefab.terrain.getTileAtWorldPos(brushWorldPos.x, brushWorldPos.y);
		if( tile == null ) return;
		var trd = new TileRevertData(tile.tileX, tile.tileY);
		trd.prevHeightMapPixels = tile.heightMap.capturePixels();
		trd.prevSurfaceIndexMapPixels = tile.surfaceIndexMap.capturePixels();
		for( w in tile.surfaceWeights )
			trd.prevWeightMapPixels.push(w.capturePixels());
		tileTrashBin.push(trd);
		terrainPrefab.terrain.removeTile(tile);
		renderTerrainUV();
	}

	public function drawSurface( pos : h3d.col.Point) {
		if( currentBrush.index == -1 ) return;
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos);
		if( brushWorldPos == null ) return;
		var c = terrainPrefab.terrain.tiles.length;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos.x, brushWorldPos.y, currentBrush.size / 2.0, autoCreateTile, allowDisconnectedTiles);
		if( c != terrainPrefab.terrain.tiles.length ) {
			renderTerrainUV();
			brushWorldPos = getBrushWorldPosFromTex(pos);
		}

		currentBrush.bitmap.color = new h3d.Vector4(1.0);
		var shader : hrt.shader.Brush = currentBrush.bitmap.getShader(hrt.shader.Brush);
		if( shader == null ) shader = currentBrush.bitmap.addShader(new hrt.shader.Brush());
		currentBrush.bitmap.blendMode = currentBrush.brushMode.accumulate ? Add : Max;
		shader.strength = currentBrush.strength;
		shader.size.set(currentBrush.size / terrainPrefab.tileSizeX, currentBrush.size / terrainPrefab.tileSizeY);

		for( tile in tiles ) {
			var strokeBuffer = weightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if( strokeBuffer.used == false ) {
				var revert = new TileRevertData(strokeBuffer.x, strokeBuffer.y);
				for( w in tile.surfaceWeights )
					revert.prevWeightMapPixels.push(w.capturePixels());
				paintRevertDatas.push(revert);
				strokeBuffer.prevTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}
			var localPos = tile.globalToLocal(brushWorldPos.clone());
			localPos.x *= 1.0 / terrainPrefab.tileSizeX;
			localPos.y *= 1.0 / terrainPrefab.tileSizeY;
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / terrainPrefab.tileSizeX * 0.5), localPos.y - (currentBrush.size  / terrainPrefab.tileSizeY * 0.5));
			currentBrush.drawTo(strokeBuffer.tex, localPos, terrainPrefab.terrain.tileSize );
		}
	}

	public function drawHeight( pos : h3d.col.Point) {
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos);
		if( brushWorldPos == null ) return;
		var c = terrainPrefab.terrain.tiles.length;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos.x, brushWorldPos.y, currentBrush.size / 2.0, autoCreateTile, allowDisconnectedTiles);
		if( c != terrainPrefab.terrain.tiles.length ) {
			renderTerrainUV();
			brushWorldPos = getBrushWorldPosFromTex(pos);
		}

		var shader : hrt.shader.Brush = currentBrush.bitmap.getShader(hrt.shader.Brush);
		if( shader == null ) shader = currentBrush.bitmap.addShader(new hrt.shader.Brush());
		currentBrush.bitmap.color = new h3d.Vector4(1.0);
		shader.size.set(currentBrush.size / terrainPrefab.tileSizeX, currentBrush.size / terrainPrefab.tileSizeY);

		switch( currentBrush.brushMode.mode ) {
			case AddSub :
				currentBrush.bitmap.blendMode = currentBrush.brushMode.accumulate ? Add : Max;
				shader.strength = currentBrush.strength;
			case Set :
				currentBrush.bitmap.blendMode = Max;
				shader.strength = 1;
			case Smooth :
				currentBrush.bitmap.blendMode = Max;
				shader.strength = 1;
			default:
		}

		for( tile in tiles ) {
			var localPos = tile.globalToLocal(brushWorldPos.clone());
			localPos.x *= 1.0 / terrainPrefab.tileSizeX;
			localPos.y *= 1.0 / terrainPrefab.tileSizeY;
			var strokeBuffer = heightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if( strokeBuffer.used == false ) {
				strokeBuffer.prevTex = tile.heightMap;
				tile.heightMap = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / terrainPrefab.tileSizeX * 0.5), localPos.y - (currentBrush.size  / terrainPrefab.tileSizeY * 0.5));
			currentBrush.drawTo(strokeBuffer.tex, localPos, terrainPrefab.terrain.tileSize, -1);
		}
	}

	public function setSelected(b : Bool ) {
		if( b ) {
			var s2d = terrainPrefab.shared.root2d.getScene();
			if( interactive == null )
				interactive.remove();
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = true;
			interactive.cancelEvents = false;

			interactive.onWheel = function(e) {
				e.propagate = true;
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY);
				renderTerrainUV();
				drawBrushPreview(worldPos);
			};

			interactive.onPush = function(e) {
				e.propagate = false;
				currentBrush.brushMode.lockDir = K.isDown(K.ALT);
				currentBrush.brushMode.subAction = K.isDown(K.SHIFT);
				currentBrush.brushMode.snapToGrid = K.isDown(K.CTRL);
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY);
				if( K.isDown( K.MOUSE_LEFT) ) {
					currentBrush.firstClick = true;
					lastPos = worldPos.clone();
					if( currentBrush.isValid() ) {
						useBrush( lastPos, worldPos);
						previewStrokeBuffers();
						drawBrushPreview(worldPos);
					}
				}
			};

			interactive.onRelease = function(e) {
				e.propagate = false;
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY);
				remainingDist = 0;
				lastPos = null;
				currentBrush.brushMode.lockAxe = NoLock;
				currentBrush.firstClick = false;
				applyStrokeBuffers();
				resetStrokeBuffers();
				drawBrushPreview(worldPos);
				checkTrashBin();
			};

			interactive.onMove = function(e) {

				// Brush Scale - Drag left/right
				if( K.isDown(K.MOUSE_RIGHT) && K.isDown(K.CTRL) ) {
					if( lastMousePos == null ) {
						lastMousePos = new h2d.col.Point(s2d.mouseX, s2d.mouseY);
						lastBrushSize = currentBrush.size;
					}
					e.propagate = false;
					var newMousePos = new h2d.col.Point(s2d.mouseX, s2d.mouseY);
					var dist = newMousePos.x - lastMousePos.x;
					var sensibility = 0.5;
					currentBrush.size = hxd.Math.max(0, lastBrushSize + sensibility * dist);
					@:privateAccess Lambda.find(editContext.properties.fields, f->f.fname=="editor.currentBrush.size").range.value = currentBrush.size;
					drawBrushPreview(getBrushPlanePos(lastMousePos.x, lastMousePos.y));
					return;
				}
				else {
					lastMousePos = null;
					lastBrushSize = 0;
				}

				currentBrush.brushMode.snapToGrid = /*K.isDown(K.CTRL)*/ false;
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY);
				if( K.isDown( K.MOUSE_LEFT) ) {
					currentBrush.firstClick = false;
					e.propagate = false;
					if( lastPos == null ) return;
					if( currentBrush.isValid() ) {
						if( currentBrush.brushMode.lockDir ){
							var dir = worldPos.sub(lastPos);
							if( currentBrush.brushMode.lockAxe == NoLock && dir.length() > 0.4 )
								currentBrush.brushMode.lockAxe = hxd.Math.abs(dir.x) > hxd.Math.abs(dir.y) ? LockX : LockY;
							if( currentBrush.brushMode.lockAxe == LockX ) {
								var distX = worldPos.sub(lastPos).x;
								worldPos.load(lastPos);
								worldPos.x += distX;
							}
							else if( currentBrush.brushMode.lockAxe == LockY ) {
								var distY = worldPos.sub(lastPos).y;
								worldPos.load(lastPos);
								worldPos.y += distY;
							}
						}
						useBrush( lastPos, worldPos);
						lastPos = worldPos;
					}
				}
				else {
					renderTerrainUV();
					e.propagate = true;
				}
				drawBrushPreview(worldPos);
			};
		}
		else {
			if( interactive != null ) interactive.remove();
			brushPreview.reset();
		}
	}

	function removeSurface( index :Int, onChange : Void -> Void ) {
		terrainPrefab.modified = true;
		var terrainRevertData = new TerrainRevertData();
		var tileRevertDatas = new Array<TileRevertData>();
		for( tile in terrainPrefab.terrain.tiles )
			tileRevertDatas.push(new TileRevertData(tile.tileX, tile.tileY));

		var oldIndexes : Array<h3d.Vector4> = [];
		var newIndexes : Array<h3d.Vector4> = [];
		for( i in 0 ... terrainPrefab.terrain.surfaces.length )
			oldIndexes.push(new h3d.Vector4(i));
		var offset = 0;
		for( i in 0 ... terrainPrefab.terrain.surfaces.length ) {
			if( i == index ) {
				offset = -1;
				newIndexes.push(new h3d.Vector4(0)); // Replace the surface removec by the surface 0
			}
			else
				newIndexes.push(new h3d.Vector4(i + offset));
		}

		swapIndex.shader.USE_ARRAY = true;
		swapIndex.shader.INDEX_COUNT = oldIndexes.length;
		swapIndex.shader.oldIndexes = oldIndexes;
		swapIndex.shader.newIndexes = newIndexes;
		var newSurfaceIndexMap = new h3d.mat.Texture(terrainPrefab.terrain.weightMapResolution.x, terrainPrefab.terrain.weightMapResolution.y, [Target], RGBA);
		for( i in 0 ... terrainPrefab.terrain.tiles.length ) {
			var tile = terrainPrefab.terrain.tiles[i];
			var revert = tileRevertDatas[i];
			revert.prevSurfaceIndexMapPixels = tile.surfaceIndexMap.capturePixels();
			for( w in tile.surfaceWeights ) revert.prevWeightMapPixels.push(w.capturePixels());
			swapIndex.shader.surfaceIndexMap = tile.surfaceIndexMap;
			h3d.Engine.getCurrent().pushTarget(newSurfaceIndexMap);
			swapIndex.render();
			copyPass.apply(newSurfaceIndexMap, tile.surfaceIndexMap);
			tile.surfaceWeights.remove(tile.surfaceWeights[index]);
			tile.generateWeightTextureArray();
		}
		terrainRevertData.surfaceIndex = index;
		terrainRevertData.surface = terrainPrefab.terrain.surfaces[index];
		terrainPrefab.terrain.surfaces.remove(terrainPrefab.terrain.surfaces[index]);
		terrainPrefab.terrain.generateSurfaceArray();

		for( i in 0 ... terrainPrefab.terrain.tiles.length ) {
			var tile = terrainPrefab.terrain.tiles[i];
			normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
			normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
			normalizeWeight.shader.baseTexIndex = 0;
			for( i in 0 ... tile.surfaceWeights.length ) {
				normalizeWeight.shader.curTexIndex = i;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
				normalizeWeight.render();
			}
			tile.generateWeightTextureArray();

			generateIndex.shader.weightTextures = tile.surfaceWeightArray;
			generateIndex.shader.weightCount = tile.surfaceWeights.length;
			h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
			generateIndex.render();

			var revert = tileRevertDatas[i];
			revert.nextSurfaceIndexMapPixels = tile.surfaceIndexMap.capturePixels();
			for( w in tile.surfaceWeights ) revert.nextWeightMapPixels.push(w.capturePixels());
		}

		onChange();

		undo.change(Custom(function(undo) {
			terrainPrefab.modified = true;
			if( undo )
				terrainPrefab.terrain.surfaces.insert(terrainRevertData.surfaceIndex, terrainRevertData.surface);
			else
				terrainPrefab.terrain.surfaces.remove(terrainRevertData.surface);
			terrainPrefab.terrain.generateSurfaceArray();

			for( revertData in tileRevertDatas ) {
				var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
				if( tile == null ) continue;
				var oldArray = tile.surfaceWeights;
				tile.surfaceWeights = new Array<h3d.mat.Texture>();
				tile.surfaceWeights = [for( i in 0...terrainPrefab.terrain.surfaces.length ) null];
				for( i in 0 ... tile.surfaceWeights.length ) {
					tile.surfaceWeights[i] = new h3d.mat.Texture(terrainPrefab.terrain.weightMapResolution.x, terrainPrefab.terrain.weightMapResolution.y, [Target], R8);
					tile.surfaceWeights[i].wrap = Clamp;
					tile.surfaceWeights[i].preventAutoDispose();
				}
				for( i in 0 ... oldArray.length )
					if( oldArray[i] != null) oldArray[i].dispose();

				tile.surfaceIndexMap.uploadPixels(undo ? revertData.prevSurfaceIndexMapPixels : revertData.nextSurfaceIndexMapPixels);

				for( i in 0 ... tile.surfaceWeights.length )
					tile.surfaceWeights[i].uploadPixels(undo ? revertData.prevWeightMapPixels[i] : revertData.nextWeightMapPixels[i]);

				tile.generateWeightTextureArray();
				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
			onChange();
		}));

	}

	function loadTexture( ctx : hide.prefab.EditContext, propsName : String, ?wrap : h3d.mat.Data.Wrap ) {
		var texture = terrainPrefab.shared.loadTexture(propsName);
		texture.wrap = wrap == null ? Repeat : wrap;
		return texture;
	}

	inline function setRange( name, value, ctx : EditContext ) {
		var field = Lambda.find(ctx.properties.fields, f->f.fname==name);
		@:privateAccess if(field != null) {
			field.current = value;
			field.range.value = value;
		}
	}

	function refreshSurfaces( props : hide.Element, ctx : EditContext ) {

		if( currentSurface == null )
			props.find('div[name="Params"]').hide();
		else
			props.find('div[name="Params"]').show();

		var surfacesContainer = props.find(".terrain-surfaces");
		surfacesContainer.empty();
		for( i in 0 ... terrainPrefab.terrain.surfaces.length ){
			var surface = terrainPrefab.terrain.surfaces[i];
			if(surface == null || surface.albedo == null) continue;
			var texName = surface.albedo.name.split(".");
			texName = texName[0].split("/");
			texName = texName[texName.length - 1].split("_Albedo");
			var label = texName[0];
			var img : Element;
			if( i == currentBrush.index) img = new Element('<div class="surface-preview-selected"></div>');
			else img = new Element('<div class="surface-preview"></div>');
			var imgPath = ctx.ide.getPath(surface.albedo.name);
			img.css("background-image", 'url("file://$imgPath")');
			var surfaceElem = new Element('<div class=" surface"><span class="tooltiptext">$label</span></div>').prepend(img);
			surfaceElem.contextmenu(function(e) {
				e.preventDefault();
				var cmi :Array< hide.comp.ContextMenu.MenuItem> = [];
				var delete : hide.comp.ContextMenu.MenuItem = {label : "Delete"};
				delete.click = function(){
					removeSurface(i, function(){refreshSurfaces(props, ctx);});
				};
				cmi.push(delete);
				hide.comp.ContextMenu.createFromEvent(cast e, cmi);
			});
			surfaceElem.click(function(e){
				editContext.scene.setCurrent();
				currentBrush.index = i;
				currentSurface = terrainPrefab.terrain.getSurface(i);
				refreshSurfaces(props, ctx);
			});
			surfacesContainer.append(surfaceElem);
		}
		if( currentSurface != null ) {
			setRange("editor.currentSurface.tilling", currentSurface.tilling, ctx);
			setRange("editor.currentSurface.offset.x", currentSurface.offset.x, ctx);
			setRange("editor.currentSurface.offset.y", currentSurface.offset.y, ctx);
			setRange("editor.currentSurface.angle", currentSurface.angle, ctx);
			setRange("editor.currentSurface.minHeight", currentSurface.minHeight, ctx);
			setRange("editor.currentSurface.maxHeight", currentSurface.maxHeight, ctx);
		}
	}

	function refreshBrushMode (props : hide.Element, ctx : EditContext ) {
		var brushIcons = ["icons/addsub.png", "icons/set.png", "icons/smooth.png", "icons/paint.png", "icons/delete.png"];
		var brushMode = [Brush.Mode.AddSub, Brush.Mode.Set, Brush.Mode.Smooth, Brush.Mode.Paint, Brush.Mode.Delete];
		var brushDescription = [
			'Raiser / Lower Terrain <br>
			<i>Click to raise, hold down shift to lower</i>',
			'Paint height <br>
			<i>Hold down shift to sample target height</i>',
			'Smooth height <br>
			<i>Paint to smooth the terrain</i>',
			'Paint surface <br>
			<i>Hold down shift to subsract</i>',
			'Delete tile <br>
			<i>Paint to delete tiles</i>'];
		var brushModeContainer = props.find(".terrain-brushModeContainer");
		brushModeContainer.empty();
		for( i in 0 ... brushIcons.length ) {
			var elem = new Element('<div class="terrain-brushMode"></div>');
			var img = new Element('<div class="terrain-brushModeIcon"></div>');
			img.css("background-image", 'url("file://${ctx.ide.getPath("${HIDE}/res/" + brushIcons[i])}")');
			elem.prepend(img);

			var select = function(_) {
				editContext.scene.setCurrent();
				var l = props.find(".terrain-brushModeIcon");
				for( e in l ) {
					var elem = new Element(e);
					elem.toggleClass("selected", false);
				}
				img.toggleClass("selected", true);
				currentBrush.brushMode.mode = brushMode[i];
				var desc = props.find(".terrain-brushModeDescription");
				desc.empty();
				desc.append(brushDescription[i]);
			};

			elem.click(select);
			if (currentBrush.brushMode.mode.equals(brushMode[i])) {
				select(null);
			}
			brushModeContainer.append(elem);
		}
	}

	var brushMode =
	'<div class="group" name="Mode">
		<div class="terrain-brushModeContainer" align="center"></div>
		<div class="terrain-brushModeDescription" align="center">
			<i> Please select a tool </i>
		</div>
		<dt>AutoCreate</dt><dd><input type="checkbox" field="autoCreateTile"/></dd>
		<dt title="Allow tiles to be created without being connected to another tile">Disconnect</dt><dd><input type="checkbox" field="allowDisconnectedTiles"/></dd>
		<dt>Accumulate</dt><dd><input type="checkbox" field="editor.currentBrush.brushMode.accumulate"/></dd>
	</div>';

	var brushParams =
	'<div class="group" name="Brush">
		<div class="terrain-brushes"></div>
		<dt>Size</dt><dd><input type="range" min="0.01" max="50" field="editor.currentBrush.size"/></dd>
		<dt>Strength</dt><dd><input type="range" min="0" max="1" field="editor.currentBrush.strength"/></dd>
		<dt>Step</dt><dd><input type="range" min="0.01" max="10" field="editor.currentBrush.step"/></dd>
		<dt>Opacity</dt><dd><input type="range" min="0" max="1" field="brushOpacity"/></dd>
	</div>';

	var surfaceParams =
	'<div class="group">
		<div class="title">Surface <input type="button" style="font-weight:bold" id="addSurface" value="+"/></div>
		<div class="terrain-surfaces"></div>
		<div class="group" name="Params">
			<dt>Tilling</dt><dd><input type="range" min="0" max="2" field="editor.currentSurface.tilling"/></dd>
			<dt>Offset X</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.x"/></dd>
			<dt>Offset Y</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.y"/></dd>
			<dt>Rotate</dt><dd><input type="range" min="0" max="360" field="editor.currentSurface.angle"/></dd>
			<dt>Min Height</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.minHeight"/></dd>
			<dt>Max Height</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.maxHeight"/></dd>
		</div>
	</div>';

	public function setupUI( props : hide.Element, ctx : EditContext ) {
		props.append(brushMode);
		props.append(brushParams);
		props.append(surfaceParams);
		props.find("#addSurface").click(function(_) {
			ctx.ide.chooseImage(onSurfaceAdd.bind(props,ctx));
		});
		refreshBrushMode(props, ctx);

		var brushes : Array<Dynamic> = ctx.scene.config.get("terrain.brushes");
		var brushesContainer = props.find(".terrain-brushes");
		function refreshBrushes() {
			brushesContainer.empty();
			for( brush in brushes ) {
				var label = brush.name + "</br>Step : " + brush.step + "</br>Strength : " + brush.strength + "</br>Size : " + brush.size ;
				var img : Element;
				if( brush.name == currentBrush.name ) img = new Element('<div class="brush-preview-selected"></div>');
				else img = new Element('<div class="brush-preview"></div>');
				img.css("background-image", 'url("file://${ctx.ide.getPath(brush.texture)}")');
				var brushElem = new Element('<div class="brush"><span class="tooltiptext">$label</span></div>').prepend(img);
				brushElem.click(function(e){
					editContext.scene.setCurrent();
					currentBrush.size = brush.size;
					currentBrush.strength = brush.strength;
					currentBrush.step = brush.step;
					currentBrush.texPath = ctx.ide.getPath(brush.texture);
					currentBrush.tex = loadTexture(ctx, currentBrush.texPath);
					currentBrush.name = brush.name;
					if( currentBrush.tex != null ) {
						if( currentBrush.bitmap != null ) {
							currentBrush.bitmap.tile.dispose();
							currentBrush.bitmap.tile = h2d.Tile.fromTexture(currentBrush.tex);
						}
						else
							currentBrush.bitmap = new h2d.Bitmap(h2d.Tile.fromTexture(currentBrush.tex));

						currentBrush.bitmap.smooth = true;
						currentBrush.bitmap.color = new h3d.Vector4(currentBrush.strength);
					}
					refreshBrushes();
				});
				brushesContainer.append(brushElem);
			}
			if( currentBrush != null ) {
				setRange("editor.currentBrush.size", currentBrush.size, ctx);
				setRange("editor.currentBrush.strength", currentBrush.strength, ctx);
				setRange("editor.currentBrush.step", currentBrush.step, ctx);
			}
		}
		refreshBrushes();
		refreshSurfaces(props, ctx);
	}

	function onSurfaceAdd( props : Element, ctx : EditContext, path : String ) {
		editContext.scene.setCurrent();
		terrainPrefab.modified = true;
		var split : Array<String> = [];
		var curTypeIndex = 0;
		while( split.length <= 1 && curTypeIndex < textureType.length) {
			split = path.split(textureType[curTypeIndex]);
			curTypeIndex++;
		}
		if( split.length <= 1 ) {
			ctx.ide.error("Invalid file name format, should be name_Albedo");
			return;
		}
		var name = split[0];
		var ext = "."+path.split(".").pop();
		var albedo = terrainPrefab.shared.loadTexture(name + textureType[0] + ext);
		var normal = terrainPrefab.shared.loadTexture(name + textureType[1] + ext);
		var pbr = terrainPrefab.shared.loadTexture(name + textureType[2] + ext);

		if( albedo == null || normal == null || pbr == null ) return;

		function wait() {
			if( albedo.flags.has(Loading) || normal.flags.has(Loading)|| pbr.flags.has(Loading))
				haxe.Timer.delay(wait, 1);
			else{
				if( terrainPrefab.terrain.getSurfaceFromTex(name + textureType[0] + ext, name + textureType[1] + ext, name + textureType[2] + ext) == null ) {
					terrainPrefab.terrain.addSurface(albedo, normal, pbr);
					terrainPrefab.terrain.generateSurfaceArray();
					refreshSurfaces(props, ctx);
					var terrainRevertData = new TerrainRevertData();
					terrainRevertData.surface = terrainPrefab.terrain.getSurface(terrainPrefab.terrain.surfaces.length - 1);
					terrainRevertData.surfaceIndex = terrainPrefab.terrain.surfaces.length - 1;
					undo.change(Custom(function(undo) {
						if( undo ) {
							terrainPrefab.terrain.surfaces.remove(terrainRevertData.surface);
							if( currentSurface == terrainRevertData.surface ) currentSurface = null;
							currentBrush.index = Std.int(hxd.Math.min(terrainPrefab.terrain.surfaces.length - 1, currentBrush.index));
						}
						else
							terrainPrefab.terrain.surfaces.push(terrainRevertData.surface);
						terrainPrefab.terrain.generateSurfaceArray();
						refreshSurfaces(props, ctx);
					}));
				}
				albedo.dispose();
				normal.dispose();
				pbr.dispose();
			}
		}
		wait();
	}

}
