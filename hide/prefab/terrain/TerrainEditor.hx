
package hide.prefab.terrain;
#if editor
using Lambda;
import hxd.Key as K;

enum RenderMode {
	PBR;
	ShaderComplexity;
	Checker;
}

class TerrainRevertData {
	public var surfaceIndex : Int;
	public var surface : h3d.scene.pbr.terrain.Surface;
	public function new(){

	}
}

class TileRevertData{
	public var x : Int;
	public var y : Int;
	public var prevHeightMapPixels : hxd.Pixels.PixelsFloat;
	public var nextHeightMapPixels : hxd.Pixels.PixelsFloat;
	public var prevWeightMapPixels : Array<hxd.Pixels> = [];
	public var nextWeightMapPixels : Array<hxd.Pixels> = [];
	public var prevSurfaceIndexMapPixels : hxd.Pixels;
	public var nextSurfaceIndexMapPixels : hxd.Pixels;
	public function new(x, y){
		this.x = x;
		this.y = y;
	}
}

class TerrainEditor {

	public var currentBrush : Brush;
	public var currentSurface : h3d.scene.pbr.terrain.Surface;
	public var tmpTexPath : String;
	public var textureType = ["_Albedo", "_Normal", "_MetallicGlossAO"];
	public var autoCreateTile = false;
	var brushPreview : hide.prefab.terrain.Brush.BrushPreview;
	var interactive : h2d.Interactive;
	var remainingDist = 0.0;
	var lastPos : h3d.Vector;
	var copyPass : h3d.pass.Copy;
	var heightStrokeBufferArray : hide.prefab.terrain.StrokeBuffer.StrokeBufferArray;
	var weightStrokeBufferArray : hide.prefab.terrain.StrokeBuffer.StrokeBufferArray;

	var normalizeWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.NormalizeWeight());
	var clampWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.ClampWeight());
	var generateIndex = new h3d.pass.ScreenFx(new hide.prefab.terrain.GenerateIndex());
	var swapIndex = new h3d.pass.ScreenFx(new hide.prefab.terrain.SwapIndex());
	var setHeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.SetHeight());
	var smoothHeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.SmoothHeight());

	var terrainPrefab : hide.prefab.terrain.Terrain;
	var undo : hide.ui.UndoHistory;
	var tileTrashBin : Array<h3d.scene.pbr.terrain.Tile> = [];
	var paintRevertDatas : Array<TileRevertData> = [];
	var uvTexPixels : hxd.Pixels.PixelsFloat;
	var uvTex : h3d.mat.Texture;
	var uvTexRes = 0.5;
	var customScene : h3d.scene.Scene;
	var customRenderer : hide.prefab.terrain.CustomRenderer;
	var renderMode : RenderMode = PBR;

	public function new(terrainPrefab, undo : hide.ui.UndoHistory){
		this.terrainPrefab = terrainPrefab;
		this.undo = undo;
		autoCreateTile = terrainPrefab.autoCreateTile;
		brushPreview = new hide.prefab.terrain.Brush.BrushPreview(terrainPrefab.terrain);
		brushPreview.refreshMesh();
		currentBrush = new Brush();
		copyPass = new h3d.pass.Copy();
		heightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(RGBA32F, terrainPrefab.heightMapResolution + 1);
		weightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(R8, terrainPrefab.weightMapResolution);
		customRenderer = new hide.prefab.terrain.CustomRenderer("terrainUV");
		customScene = new h3d.scene.Scene();
		customScene.renderer = customRenderer;
		#if debug
		customScene.checkPasses = false;
		#end
	}

	public function dispose(){
		if(uvTex != null) uvTex.dispose();
		heightStrokeBufferArray.dispose();
		weightStrokeBufferArray.dispose();
		brushPreview.dispose();
	}

	public function update( ?propName : String ) {
		if(propName == "editor.currentSurface.tilling"
		|| propName == "editor.currentSurface.offset.x"
		|| propName == "editor.currentSurface.offset.y"
		|| propName == "editor.currentSurface.angle")
			terrainPrefab.terrain.updateSurfaceParams();
		autoCreateTile = terrainPrefab.autoCreateTile;
		if(propName == "editor.renderMode") updateRender();
	}

	public function refresh(){
		brushPreview.refreshMesh();
		heightStrokeBufferArray.refresh(terrainPrefab.heightMapResolution + 1);
		weightStrokeBufferArray.refresh(terrainPrefab.weightMapResolution);
	}

	function updateRender(){
		for(tile in terrainPrefab.terrain.tiles)
			tile.material.removePass(tile.material.getPass("overlay"));
		terrainPrefab.terrain.showChecker = false;
		terrainPrefab.terrain.showComplexity = false;
		switch(renderMode){
			case PBR :
			case ShaderComplexity : terrainPrefab.terrain.showComplexity = true;
			case Checker : terrainPrefab.terrain.showChecker = true;
		}
	}

	function renderTerrainUV(ctx : Context){
		if(customScene == null) return;
		var engine = h3d.Engine.getCurrent();
		var mainScene = @:privateAccess ctx.local3d.getScene();

		if(uvTex == null || uvTex.width != Std.int(h3d.Engine.getCurrent().width * uvTexRes) || uvTex.height != Std.int(h3d.Engine.getCurrent().height * uvTexRes)){
			if(uvTex != null) {
				uvTex.depthBuffer.dispose();
				uvTex.dispose();
			}
			uvTex = new h3d.mat.Texture( Std.int(h3d.Engine.getCurrent().width * uvTexRes),  Std.int(h3d.Engine.getCurrent().height * uvTexRes), [Target], RGBA32F);
			uvTex.depthBuffer = new h3d.mat.DepthBuffer(uvTex.width, uvTex.height);
		}

		customScene.addChild(terrainPrefab.terrain);
		customScene.camera = mainScene.camera;
		brushPreview.reset();

		var tiles = terrainPrefab.terrain.getVisibleTiles(mainScene.camera);
		for(i in 0 ... tiles.length){
			var tile = tiles[i];
			var p = new h3d.mat.Pass("terrainUV");
			p.addShader(new h3d.shader.BaseMesh());
			p.depthTest = Less;
			p.culling = None;
			p.depthWrite = true;
			tile.material.addPass(p);
			var s = new hide.prefab.terrain.CustomUV();
			s.primSize = terrainPrefab.terrain.tileSize;
			s.heightMapSize = terrainPrefab.heightMapResolution;
			s.heightMap = tile.heightMap;
			s.tileIndex = i;
			p.addShader(s);
		}

		engine.begin();
		engine.pushTarget(uvTex);
		engine.clear(0xffffff,1,0);
		engine.clearF(new h3d.Vector(-1, -1, -1, -1),1,0);
		customScene.render(engine);
		engine.popTarget();

		for(tile in tiles)
			tile.material.removePass(tile.material.getPass("terrainUV"));

		mainScene.addChild(terrainPrefab.terrain);
		customScene.camera = null;

		uvTexPixels = uvTex.capturePixels();
	}

	function checkTrashBin(){
		if(tileTrashBin.length > 0){
			var tileTrashBinTmp = tileTrashBin.copy();
			tileTrashBin = [];
			undo.change(Custom(function(undo) {
				for(t in tileTrashBinTmp){
					undo ? terrainPrefab.terrain.addTile(t, true) : terrainPrefab.terrain.removeTile(t);
				}
			}));
			tileTrashBin = [];
		}
	}

	function resetStrokeBuffers(){
		heightStrokeBufferArray.reset();
		weightStrokeBufferArray.reset();
	}

	function applyStrokeBuffers(){
		var revertDatas = new Array<TileRevertData>();
		for(strokeBuffer in heightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.heightMap;
				tile.heightMap = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;
				var revert = new TileRevertData(strokeBuffer.x, strokeBuffer.y);
				revert.prevHeightMapPixels = tile.getHeightPixels();

				switch(currentBrush.brushMode.mode){
					case AddSub :
						copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.subAction ? Sub : Add);
						tile.needNewPixelCapture = true;
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

				tile.needNewPixelCapture = true;
				revert.nextHeightMapPixels = tile.getHeightPixels();
				revertDatas.push(revert);
			}
		}
		for(strokeBuffer in heightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				tile.blendEdges();
			}
		}
		terrainPrefab.terrain.refreshTiles();

		if(revertDatas.length > 0){
			undo.change(Custom(function(undo) {
				for(revertData in revertDatas){
					var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
					if(tile == null) continue;
					tile.heightMap.uploadPixels(undo ? revertData.prevHeightMapPixels : revertData.nextHeightMapPixels);
					tile.needNewPixelCapture = true;
				}
				for(revertData in revertDatas){
					var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
					if(tile == null) continue;
					tile.blendEdges();
				}
				terrainPrefab.terrain.refreshTiles();
			}));
		}

		for(strokeBuffer in weightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;

				copyPass.apply(strokeBuffer.tex, tile.surfaceWeights[currentBrush.index], currentBrush.brushMode.subAction ? Sub : Add);
				tile.generateWeightArray();

				clampWeight.shader.weightTextures = tile.surfaceWeightArray;
				clampWeight.shader.weightCount = tile.surfaceWeights.length;
				clampWeight.shader.baseTexIndex = currentBrush.index;
				for(i in 0 ... tile.surfaceWeights.length){
					if(i == currentBrush.index) continue;
					clampWeight.shader.curTexIndex = i;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
					clampWeight.render();
				}
				tile.generateWeightArray();

				normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
				normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
				normalizeWeight.shader.baseTexIndex = currentBrush.index;
				for(i in 0 ... tile.surfaceWeights.length){
					normalizeWeight.shader.curTexIndex = i;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
					normalizeWeight.render();
				}
				tile.generateWeightArray();

				var revert : TileRevertData = null;
				for(r in paintRevertDatas)
					if(r.x == strokeBuffer.x && r.y == strokeBuffer.y){
						revert = r;
						break;
					}
				if(revert != null)
					for(w in tile.surfaceWeights)
						revert.nextWeightMapPixels.push(w.capturePixels());

				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
		}

		if(paintRevertDatas.length > 0){
			var paintRevertdataTmp = paintRevertDatas.copy();
			paintRevertDatas = [];
			undo.change(Custom(function(undo) {
				for(revertData in paintRevertdataTmp){
					var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
					if(tile == null) continue;
					for(i in 0 ... tile.surfaceWeights.length)
						tile.surfaceWeights[i].uploadPixels(undo ? revertData.prevWeightMapPixels[i] : revertData.nextWeightMapPixels[i]);
					tile.generateWeightArray();
					generateIndex.shader.weightTextures = tile.surfaceWeightArray;
					generateIndex.shader.weightCount = tile.surfaceWeights.length;
					h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
					generateIndex.render();
				}
			}));
		}
	}

	function previewStrokeBuffers(){
		for(strokeBuffer in heightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				switch(currentBrush.brushMode.mode){
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

		for(strokeBuffer in weightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				copyPass.apply(strokeBuffer.prevTex, strokeBuffer.tempTex);
				copyPass.apply(strokeBuffer.tex, strokeBuffer.tempTex, currentBrush.brushMode.subAction ? Sub : Add);
				tile.generateWeightArray();

				var engine = h3d.Engine.getCurrent();
				clampWeight.shader.weightTextures = tile.surfaceWeightArray;
				clampWeight.shader.weightCount = tile.surfaceWeights.length;
				clampWeight.shader.baseTexIndex = currentBrush.index;
				for(i in 0 ... tile.surfaceWeights.length){
					if(i == currentBrush.index) continue;
					clampWeight.shader.curTexIndex = i;
					engine.pushTarget(tile.surfaceWeights[i]);
					clampWeight.render();
				}
				tile.generateWeightArray();

				normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
				normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
				normalizeWeight.shader.baseTexIndex = currentBrush.index;
				for(i in 0 ... tile.surfaceWeights.length){
					normalizeWeight.shader.curTexIndex = i;
					engine.pushTarget(tile.surfaceWeights[i]);
					normalizeWeight.render();
				}
				tile.generateWeightArray();

				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				engine.pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
		}
	}

	function projectToGround(ray: h3d.col.Ray) {
		var minDist = -1.;
		var normal = terrainPrefab.terrain.getAbsPos().up();
		var plane = h3d.col.Plane.fromNormalPoint(normal.toPoint(), new h3d.col.Point(terrainPrefab.terrain.getAbsPos().tx, terrainPrefab.terrain.getAbsPos().ty, terrainPrefab.terrain.getAbsPos().tz));
		var pt = ray.intersect(plane);
		if(pt != null) { minDist = pt.sub(ray.getPos()).length();}
		return minDist;
	}

	function screenToWorld( u : Float, v : Float, ctx : Context) {
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		var ray = camera.rayFromScreen(u, v);
		var dist = projectToGround(ray);
		return dist >= 0 ? ray.getPoint(dist) : null;
	}

	function worldToScreen(wx: Float, wy: Float, wz: Float, ctx : Context) {
		var s2d = @:privateAccess ctx.local2d.getScene();
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		var pt = camera.project(wx, wy, wz, s2d.width, s2d.height);
		return new h2d.col.Point( hxd.Math.abs(pt.x), hxd.Math.abs(pt.y));
	}

	function getBrushPlanePos(mouseX, mouseY, ctx){
		var worldPos = screenToWorld(mouseX, mouseY, ctx).toVector();
		if(currentBrush.brushMode.snapToGrid){
			var localPos = terrainPrefab.terrain.globalToLocal(worldPos.clone());
			localPos.x = hxd.Math.round(localPos.x / terrainPrefab.terrain.cellSize) * terrainPrefab.terrain.cellSize;
			localPos.y = hxd.Math.round(localPos.y / terrainPrefab.terrain.cellSize) * terrainPrefab.terrain.cellSize;
			localPos.z = hxd.Math.round(localPos.z / terrainPrefab.terrain.cellSize) * terrainPrefab.terrain.cellSize;
			worldPos = terrainPrefab.terrain.globalToLocal(localPos.clone());
		}
		return worldPos;
	}

	function getBrushWorldPosFromTex(worldPos : h3d.Vector, ctx : Context) : h3d.Vector {
		if(currentBrush.brushMode.snapToGrid) return worldPos;
		var screenPos = worldToScreen(worldPos.x, worldPos.y, worldPos.z, ctx);
		var brushWorldPos : h3d.Vector = worldPos.clone();
		var fetchPos = new h2d.col.Point(hxd.Math.floor(screenPos.x * uvTexRes), hxd.Math.floor(screenPos.y * uvTexRes));
		fetchPos.x = hxd.Math.clamp(fetchPos.x, 0, uvTexPixels.width - 1);
		fetchPos.y = hxd.Math.clamp(fetchPos.y, 0, uvTexPixels.height - 1);
		var pixel = uvTexPixels.getPixelF( Std.int(fetchPos.x), Std.int(fetchPos.y));
		var tiles = terrainPrefab.terrain.getVisibleTiles(@:privateAccess ctx.local3d.getScene().camera);
		for(i in 0 ... tiles.length)
			if( hxd.Math.ceil(pixel.z) == i)
				brushWorldPos = tiles[i].localToGlobal(new h3d.Vector(pixel.x * terrainPrefab.tileSize, pixel.y * terrainPrefab.tileSize, 0));
		return brushWorldPos;
	}

	function drawBrushPreview( worldPos : h3d.Vector, ctx : Context){
		brushPreview.reset();
		if(currentBrush.brushMode.mode == Delete || currentBrush.bitmap == null) return;
		var brushWorldPos = uvTexPixels == null ? worldPos : getBrushWorldPosFromTex(worldPos, ctx);
		if(brushWorldPos == null) return;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos.x, brushWorldPos.y, currentBrush.size / 2.0 , false);
		for(i in 0 ... tiles.length){
			var tile = tiles[i];
			var brushPos = tile.globalToLocal(brushWorldPos.clone());
			brushPos.scale3(1.0 / terrainPrefab.tileSize);
			brushPreview.addPreviewMeshAt(tile.tileX, tile.tileY, currentBrush, brushPos, ctx);
		}
	}

	function applyBrush(pos, ctx : Context){
		switch (currentBrush.brushMode.mode){
			case Paint: drawSurface(pos, ctx);
			case AddSub: drawHeight(pos, ctx);
			case Smooth: drawHeight(pos, ctx);
			case Set: drawHeight(pos, ctx);
			case Delete: deleteTile(pos, ctx);
			default:
		}
	}

	function useBrush( from : h3d.Vector, to : h3d.Vector, ctx : Context){
		var dist = (to.sub(from)).length();
		if(currentBrush.firstClick){
			if( currentBrush.brushMode.mode == Set ){
				if( currentBrush.brushMode.subAction )
					currentBrush.brushMode.setHeightValue = terrainPrefab.terrain.getHeight(from.x, from.y);
				else
					currentBrush.brushMode.setHeightValue = currentBrush.strength;
			}
			applyBrush(from, ctx);
			previewStrokeBuffers();
			return;
		}
		var dist = (to.sub(from)).length();
		if(dist + remainingDist >= currentBrush.step){
			var dir = to.sub(from);
			dir.normalize();
			var pos = from.clone();
			var step = dir.clone();
			step.scale3(currentBrush.step);
			while(dist + remainingDist >= currentBrush.step){
				if(remainingDist > 0){
					var firstStep = dir.clone();
					firstStep.scale3(currentBrush.step - remainingDist);
					pos = pos.add(firstStep);
				}else
					pos = pos.add(step);
				applyBrush(pos, ctx);
				dist -= currentBrush.step - remainingDist;
				remainingDist = 0;
			}
			remainingDist = dist;
			previewStrokeBuffers();
		}else
			remainingDist += dist;
	}

	public function deleteTile(pos : h3d.Vector, ctx : Context){
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos, ctx);
		if(brushWorldPos == null) return;
		var tile = terrainPrefab.terrain.getTileAtWorldPos(brushWorldPos.x, brushWorldPos.y);
		if(tile == null) return;
		terrainPrefab.terrain.removeTile(tile);
		tileTrashBin.push(tile);
		renderTerrainUV(ctx);
	}

	public function drawSurface(pos : h3d.Vector, ctx : Context){
		if(currentBrush.index == -1) return;
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos, ctx);
		if(brushWorldPos == null) return;
		var c = terrainPrefab.terrain.tiles.length;
		var tiles = terrainPrefab.terrain.getTiles(pos.x, pos.y, currentBrush.size / 2.0, autoCreateTile);
		if(c != terrainPrefab.terrain.tiles.length){
			renderTerrainUV(ctx);
			brushWorldPos = getBrushWorldPosFromTex(pos, ctx);
		}

		currentBrush.bitmap.color = new h3d.Vector(1.0);
		var shader : h3d.shader.pbr.Brush = currentBrush.bitmap.getShader(h3d.shader.pbr.Brush);
		if( shader == null ) shader = currentBrush.bitmap.addShader(new h3d.shader.pbr.Brush());
		currentBrush.bitmap.blendMode = currentBrush.brushMode.accumulate ? Add : Max;
		shader.strength = currentBrush.strength;
		shader.size = currentBrush.size / terrainPrefab.tileSize;

		for(tile in tiles){
			var strokeBuffer = weightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if(strokeBuffer.used == false){
				var revert = new TileRevertData(strokeBuffer.x, strokeBuffer.y);
				for(w in tile.surfaceWeights)
					revert.prevWeightMapPixels.push(w.capturePixels());
				paintRevertDatas.push(revert);
				strokeBuffer.prevTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}
			var localPos = tile.globalToLocal(brushWorldPos.clone());
			localPos.scale3(1.0 / terrainPrefab.tileSize);
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / terrainPrefab.tileSize * 0.5), localPos.y - (currentBrush.size  / terrainPrefab.tileSize * 0.5));
			currentBrush.drawTo(strokeBuffer.tex, localPos, terrainPrefab.tileSize);
		}
	}

	public function drawHeight(pos : h3d.Vector, ctx : Context){
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(pos, ctx);
		if(brushWorldPos == null) return;
		var c = terrainPrefab.terrain.tiles.length;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos.x, brushWorldPos.y, currentBrush.size / 2.0, autoCreateTile);
		if(c != terrainPrefab.terrain.tiles.length){
			renderTerrainUV(ctx);
			brushWorldPos = getBrushWorldPosFromTex(pos, ctx);
		}

		var shader : h3d.shader.pbr.Brush = currentBrush.bitmap.getShader(h3d.shader.pbr.Brush);
		if( shader == null ) shader = currentBrush.bitmap.addShader(new h3d.shader.pbr.Brush());
		currentBrush.bitmap.color = new h3d.Vector(1.0);
		shader.size = currentBrush.size / terrainPrefab.tileSize;

		switch(currentBrush.brushMode.mode){
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

		for(tile in tiles){
			var localPos = tile.globalToLocal(brushWorldPos.clone());
			localPos.scale3(1.0 / terrainPrefab.tileSize);
			var strokeBuffer = heightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if(strokeBuffer.used == false){
				strokeBuffer.prevTex = tile.heightMap;
				tile.heightMap = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / terrainPrefab.tileSize * 0.5), localPos.y - (currentBrush.size  / terrainPrefab.tileSize * 0.5));
			currentBrush.drawTo(strokeBuffer.tex, localPos, terrainPrefab.tileSize, -1);
		}
	}

	public function setSelected( ctx : Context, b : Bool ) {
		if(b){
			var s2d = @:privateAccess ctx.local2d.getScene();
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = true;
			interactive.cancelEvents = false;

			interactive.onWheel = function(e) {
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY, ctx);
				renderTerrainUV(ctx);
				drawBrushPreview(worldPos, ctx);
			};

			interactive.onPush = function(e) {
				currentBrush.brushMode.lockDir = K.isDown(K.ALT);
				currentBrush.brushMode.subAction = K.isDown(K.SHIFT);
				currentBrush.brushMode.snapToGrid = K.isDown(K.CTRL);
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY, ctx);
				if(K.isDown( K.MOUSE_LEFT)){
					currentBrush.firstClick = true;
					e.propagate = false;
					lastPos = worldPos.clone();
					if(currentBrush.isValid()){
						useBrush( lastPos, worldPos, ctx);
						previewStrokeBuffers();
						drawBrushPreview(worldPos, ctx);
					}
				}
			};

			interactive.onRelease = function(e) {
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY, ctx);
				remainingDist = 0;
				lastPos = null;
				currentBrush.brushMode.lockAxe = NoLock;
				currentBrush.firstClick = false;
				applyStrokeBuffers();
				resetStrokeBuffers();
				drawBrushPreview(worldPos, ctx);
				checkTrashBin();
			};

			interactive.onMove = function(e) {
				currentBrush.brushMode.snapToGrid = K.isDown(K.CTRL);
				var worldPos = getBrushPlanePos(s2d.mouseX, s2d.mouseY, ctx);

				if( K.isDown( K.MOUSE_LEFT) ){
					currentBrush.firstClick = false;
					e.propagate = false;
					if( lastPos == null ) return;
					if( currentBrush.isValid() ){
						if( currentBrush.brushMode.lockDir ){
							var dir = worldPos.sub(lastPos);
							trace(dir);
							if( currentBrush.brushMode.lockAxe == NoLock && dir.length() > 0.4 )
								currentBrush.brushMode.lockAxe = hxd.Math.abs(dir.x) > hxd.Math.abs(dir.y) ? LockX : LockY;
							if( currentBrush.brushMode.lockAxe == LockX ){
								var distX = worldPos.sub(lastPos).x;
								worldPos.load(lastPos);
								worldPos.x += distX;
							}
							else if( currentBrush.brushMode.lockAxe == LockY ){
								var distY = worldPos.sub(lastPos).y;
								worldPos.load(lastPos);
								worldPos.y += distY;
							}
						}
						useBrush( lastPos, worldPos, ctx);
						lastPos = worldPos;
					}
				}
				else
					renderTerrainUV(ctx);
				drawBrushPreview(worldPos, ctx);
			};
		}
		else{
			if(interactive != null) interactive.remove();
			brushPreview.reset();
		}
	}

	function removeSurface(index :Int, onChange : Void -> Void){

		var terrainRevertData = new TerrainRevertData();
		var tileRevertDatas = new Array<TileRevertData>();
		for(tile in terrainPrefab.terrain.tiles)
			tileRevertDatas.push(new TileRevertData(tile.tileX, tile.tileY));

		var oldIndexes : Array<h3d.Vector> = [];
		var newIndexes : Array<h3d.Vector> = [];
		for(i in 0 ... terrainPrefab.terrain.surfaces.length)
			oldIndexes.push(new h3d.Vector(i));
		var offset = 0;
		for(i in 0 ... terrainPrefab.terrain.surfaces.length){
			if(i == index) {
				offset = -1;
				newIndexes.push(new h3d.Vector(0));
			}
			else
				newIndexes.push(new h3d.Vector(i + offset));
		}

		swapIndex.shader.USE_ARRAY = true;
		swapIndex.shader.INDEX_COUNT = oldIndexes.length;
		swapIndex.shader.oldIndexes = oldIndexes;
		swapIndex.shader.newIndexes = newIndexes;
		var newSurfaceIndexMap = new h3d.mat.Texture(terrainPrefab.weightMapResolution, terrainPrefab.weightMapResolution, [Target], RGBA);
		for(i in 0 ... terrainPrefab.terrain.tiles.length){
			var tile = terrainPrefab.terrain.tiles[i];
			var revert = tileRevertDatas[i];
			revert.prevSurfaceIndexMapPixels = tile.surfaceIndexMap.capturePixels();
			for(w in tile.surfaceWeights) revert.prevWeightMapPixels.push(w.capturePixels());
			swapIndex.shader.surfaceIndexMap = tile.surfaceIndexMap;
			h3d.Engine.getCurrent().pushTarget(newSurfaceIndexMap);
			swapIndex.render();
			copyPass.apply(newSurfaceIndexMap, tile.surfaceIndexMap);
			tile.surfaceWeights.remove(tile.surfaceWeights[index]);
			tile.generateWeightArray();
		}
		terrainRevertData.surfaceIndex = index;
		terrainRevertData.surface = terrainPrefab.terrain.surfaces[index];
		terrainPrefab.terrain.surfaces.remove(terrainPrefab.terrain.surfaces[index]);
		terrainPrefab.terrain.generateSurfaceArray();

		for(i in 0 ... terrainPrefab.terrain.tiles.length){
			var tile = terrainPrefab.terrain.tiles[i];
			normalizeWeight.shader.weightTextures = tile.surfaceWeightArray;
			normalizeWeight.shader.weightCount = tile.surfaceWeights.length;
			normalizeWeight.shader.baseTexIndex = 0;
			for(i in 0 ... tile.surfaceWeights.length){
				normalizeWeight.shader.curTexIndex = i;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
				normalizeWeight.render();
			}
			tile.generateWeightArray();

			generateIndex.shader.weightTextures = tile.surfaceWeightArray;
			generateIndex.shader.weightCount = tile.surfaceWeights.length;
			h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
			generateIndex.render();

			var revert = tileRevertDatas[i];
			revert.nextSurfaceIndexMapPixels = tile.surfaceIndexMap.capturePixels();
			for(w in tile.surfaceWeights) revert.nextWeightMapPixels.push(w.capturePixels());
		}

		onChange();

		undo.change(Custom(function(undo) {
			if(undo)
				terrainPrefab.terrain.surfaces.insert(terrainRevertData.surfaceIndex, terrainRevertData.surface);
			else
				terrainPrefab.terrain.surfaces.remove(terrainRevertData.surface);
			terrainPrefab.terrain.generateSurfaceArray();

			for(revertData in tileRevertDatas){
				var tile = terrainPrefab.terrain.getTile(revertData.x, revertData.y);
				if(tile == null) continue;
				var oldArray = tile.surfaceWeights;
				tile.surfaceWeights = new Array<h3d.mat.Texture>();
				tile.surfaceWeights = [for (i in 0...terrainPrefab.terrain.surfaces.length) null];
				for(i in 0 ... tile.surfaceWeights.length){
					tile.surfaceWeights[i] = new h3d.mat.Texture(terrainPrefab.weightMapResolution, terrainPrefab.weightMapResolution, [Target], R8);
					tile.surfaceWeights[i].wrap = Clamp;
					tile.surfaceWeights[i].preventAutoDispose();
				}
				for(i in 0 ... oldArray.length)
					if( oldArray[i] != null) oldArray[i].dispose();

				tile.surfaceIndexMap.uploadPixels(undo ? revertData.prevSurfaceIndexMapPixels : revertData.nextSurfaceIndexMapPixels);

				for(i in 0 ... tile.surfaceWeights.length)
					tile.surfaceWeights[i].uploadPixels(undo ? revertData.prevWeightMapPixels[i] : revertData.nextWeightMapPixels[i]);

				tile.generateWeightArray();
				generateIndex.shader.weightTextures = tile.surfaceWeightArray;
				generateIndex.shader.weightCount = tile.surfaceWeights.length;
				h3d.Engine.getCurrent().pushTarget(tile.surfaceIndexMap);
				generateIndex.render();
			}
			onChange();
		}));

	}

	function loadTexture( ctx : hide.prefab.EditContext, propsName : String, ?wrap : h3d.mat.Data.Wrap){
		var texture = ctx.rootContext.shared.loadTexture(propsName);
		texture.wrap = wrap == null ? Repeat : wrap;
		return texture;
	}

	inline function setRange(name, value, ctx : EditContext){
		var field = Lambda.find(ctx.properties.fields, f->f.fname==name);
		if(field != null) @:privateAccess field.range.value = value;
	}

	function refreshSurfaces(props : hide.Element, ctx : EditContext){
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
				var cmi :Array< hide.comp.ContextMenu.ContextMenuItem> = [];
				var delete : hide.comp.ContextMenu.ContextMenuItem = {label : "Delete"};
				delete.click = function(){
					removeSurface(i, function(){refreshSurfaces(props, ctx);});
				};
				cmi.push(delete);
				var cm = new hide.comp.ContextMenu(cmi);
			});
			surfaceElem.click(function(e){
				currentBrush.index = i;
				currentSurface = terrainPrefab.terrain.getSurface(i);
				refreshSurfaces(props, ctx);
			});
			surfacesContainer.append(surfaceElem);
		}
		if(currentSurface != null){
			setRange("editor.currentSurface.tilling", currentSurface.tilling, ctx);
			setRange("editor.currentSurface.offset.x", currentSurface.offset.x, ctx);
			setRange("editor.currentSurface.offset.y", currentSurface.offset.y, ctx);
			setRange("editor.currentSurface.angle", currentSurface.angle, ctx);
		}
	}

	function refreshBrushMode(props : hide.Element, ctx : EditContext){
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
			<i>hold down shift to subsract</i>',
			'Delete tile <br>
			<i>Paint to delete tiles</i>'];
		var brushModeContainer = props.find(".terrain-brushModeContainer");
		brushModeContainer.empty();
		for( i in 0 ... brushIcons.length){
			var elem = new Element('<div class="terrain-brushMode"></div>');
			var img = new Element('<div class="terrain-brushModeIcon"></div>');
			img.css("background-image", 'url("file://${ctx.ide.getPath("${HIDE}/res/" + brushIcons[i])}")');
			elem.prepend(img);
			elem.click(function(_) {
				var l = props.find(".terrain-brushModeIcon");
				for(e in l){
					var elem = new Element(e);
					elem.toggleClass("selected", false);
				}
				img.toggleClass("selected", true);
				currentBrush.brushMode.mode = brushMode[i];
				var desc = props.find(".terrain-brushModeDescription");
				desc.empty();
				desc.append(brushDescription[i]);

			});
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
		<dt>Accumulate</dt><dd><input type="checkbox" field="editor.currentBrush.brushMode.accumulate"/></dd>
	</div>';

	var brushParams =
	'<div class="group" name="Brush">
		<div class="terrain-brushes"></div>
		<dt>Size</dt><dd><input type="range" min="0.01" max="50" field="editor.currentBrush.size"/></dd>
		<dt>Strength</dt><dd><input type="range" min="0" max="1" field="editor.currentBrush.strength"/></dd>
		<dt>Step</dt><dd><input type="range" min="0.01" max="10" field="editor.currentBrush.step"/></dd>
	</div>';

	var surfaceParams =
	'<div class="group" name="Surface">
		<dt>Add</dt><dd><input type="texturepath" field="editor.tmpTexPath"/></dd>
		<div class="terrain-surfaces"></div>
		<div class="group" name="Params">
			<dt>Tilling</dt><dd><input type="range" min="0" max="20" field="editor.currentSurface.tilling"/></dd>
			<dt>Offset X</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.x"/></dd>
			<dt>Offset Y</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.y"/></dd>
			<dt>Rotate</dt><dd><input type="range" min="0" max="360" field="editor.currentSurface.angle"/></dd>
		</div>
	</div>';

	public function setupUI(props : hide.Element, ctx : EditContext){
		props.append(brushMode);
		props.append(brushParams);
		props.append(surfaceParams);
		refreshBrushMode(props, ctx);
		props.append(
			'<div align="center">
				<input type="button" value="Save" class="save" />
			</div>');

		// Save Button
		props.find(".save").click(function(_) {
			var datPath = new haxe.io.Path(ctx.rootContext.shared.currentPath);
			datPath.ext = "dat";
			var fullPath = ctx.ide.getPath(datPath.toString() + "/" + terrainPrefab.name);
			if( sys.FileSystem.isDirectory(fullPath)){
				var files = sys.FileSystem.readDirectory(fullPath);
				for(file in files)
					sys.FileSystem.deleteFile(fullPath + "/" + file);
			}
			terrainPrefab.saveWeightTextures(ctx.rootContext);
			terrainPrefab.saveHeightTextures(ctx.rootContext);
		});

		var brushes : Array<Dynamic> = ctx.scene.config.get("terrain.brushes");
		var brushesContainer = props.find(".terrain-brushes");
		function refreshBrushes(){
			brushesContainer.empty();
			for( brush in brushes){
				var label = brush.name + "</br>Step : " + brush.step + "</br>Strength : " + brush.strength + "</br>Size : " + brush.size ;
				var img : Element;
				if( brush.name == currentBrush.name) img = new Element('<div class="brush-preview-selected"></div>');
				else img = new Element('<div class="brush-preview"></div>');
				img.css("background-image", 'url("file://${ctx.ide.getPath(brush.texture)}")');
				var brushElem = new Element('<div class="brush"><span class="tooltiptext">$label</span></div>').prepend(img);
				brushElem.click(function(e){
					currentBrush.size = brush.size;
					currentBrush.strength = brush.strength;
					currentBrush.step = brush.step;
					currentBrush.texPath = ctx.ide.getPath(brush.texture);
					currentBrush.tex = loadTexture(ctx, currentBrush.texPath);
					currentBrush.name = brush.name;
					if(currentBrush.bitmap != null){
						currentBrush.bitmap.tile.dispose();
						currentBrush.bitmap.tile = h2d.Tile.fromTexture(currentBrush.tex);
					}
					else
						currentBrush.bitmap = new h2d.Bitmap(h2d.Tile.fromTexture(currentBrush.tex));
					currentBrush.bitmap.smooth = true;
					currentBrush.bitmap.color = new h3d.Vector(currentBrush.strength);
					refreshBrushes();
				});
				brushesContainer.append(brushElem);
			}
			if(currentBrush != null){
				setRange("editor.currentBrush.size", currentBrush.size, ctx);
				setRange("editor.currentBrush.strength", currentBrush.strength, ctx);
				setRange("editor.currentBrush.step", currentBrush.step, ctx);
			}
		}
		refreshBrushes();
		refreshSurfaces(props, ctx);
	}

	public function onChange(ctx : EditContext, pname, props){
		if(pname == "editor.tmpTexPath" && tmpTexPath != null){
			var split : Array<String> = [];
			var curTypeIndex = 0;
			while( split.length <= 1 && curTypeIndex < textureType.length){
				split = tmpTexPath.split(textureType[curTypeIndex]);
				curTypeIndex++;
			}
			if(split.length > 1) {
				var name = split[0];
				var albedo = ctx.rootContext.shared.loadTexture(name + textureType[0] + ".png");
				var normal = ctx.rootContext.shared.loadTexture(name + textureType[1] + ".png");
				var pbr = ctx.rootContext.shared.loadTexture(name + textureType[2] + ".png");
				function wait() {
					if( albedo.flags.has(Loading) || normal.flags.has(Loading)|| pbr.flags.has(Loading))
						haxe.Timer.delay(wait, 1);
					else{
						if(terrainPrefab.terrain.getSurfaceFromTex(name + textureType[0] + ".png", name + textureType[1] + ".png", name + textureType[2] + ".png") == null){
							terrainPrefab.terrain.addSurface(albedo, normal, pbr);
							terrainPrefab.terrain.generateSurfaceArray();
							refreshSurfaces(props, ctx);
							var terrainRevertData = new TerrainRevertData();
							terrainRevertData.surface = terrainPrefab.terrain.getSurface(terrainPrefab.terrain.surfaces.length - 1);
							terrainRevertData.surfaceIndex = terrainPrefab.terrain.surfaces.length - 1;
							undo.change(Custom(function(undo) {
								if(undo){
									terrainPrefab.terrain.surfaces.remove(terrainRevertData.surface);
									if(currentSurface == terrainRevertData.surface) currentSurface = null;
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
		tmpTexPath = null;
	}
}

#end