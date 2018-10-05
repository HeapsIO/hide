package hide.prefab.terrain;
using Lambda;
import hxd.Key as K;

class TileRevertData{
	public var x : Int;
	public var y : Int;
	public var prevHeightMapPixels : hxd.Pixels.PixelsFloat;
	public var nextHeightMapPixels : hxd.Pixels.PixelsFloat;
	public var prevWeightMapPixels : Array<hxd.Pixels> = [];
	public var nextWeightMapPixels : Array<hxd.Pixels> = [];
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
	var terrainPrefab : hide.prefab.terrain.Terrain;
	var undo : hide.ui.UndoHistory;
	var tileTrashBin : Array<h3d.scene.pbr.terrain.Tile> = [];
	var paintRevertDatas : Array<TileRevertData> = [];
	var uvTexPixels : hxd.Pixels;
	var uvTex : h3d.mat.Texture;
	var customScene : h3d.scene.Scene;

	public function new(terrainPrefab, undo : hide.ui.UndoHistory){
		this.terrainPrefab = terrainPrefab;
		this.undo = undo;
		brushPreview = new hide.prefab.terrain.Brush.BrushPreview(terrainPrefab.terrain);
		brushPreview.refreshMesh();
		currentBrush = new Brush();
		copyPass = new h3d.pass.Copy();
		heightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(RGBA32F, terrainPrefab.heightMapResolution + 1);
		weightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(R8, terrainPrefab.weightMapResolution);
		customScene = new h3d.scene.Scene();
	}

	public function update( ?propName : String ) {
		if(propName == "tileSize" || propName == "cellSize"){
			brushPreview.refreshMesh();
		}
		else if(propName == "heightMapResolution" || propName == "weightMapResolution"){
			heightStrokeBufferArray.refresh(terrainPrefab.heightMapResolution + 1);
			weightStrokeBufferArray.refresh(terrainPrefab.weightMapResolution);
		}
		autoCreateTile = terrainPrefab.autoCreateTile;
	}

	function renderTerrainUV(ctx : Context){
		var engine = h3d.Engine.getCurrent();
		var mainScene = @:privateAccess ctx.local3d.getScene();

		if(uvTex == null || uvTex.width != Std.int(h3d.Engine.getCurrent().width * 0.5) || uvTex.height != Std.int(h3d.Engine.getCurrent().height * 0.5)){
			if(uvTex != null) uvTex.dispose();
			uvTex = new h3d.mat.Texture( Std.int(h3d.Engine.getCurrent().width * 0.5),  Std.int(h3d.Engine.getCurrent().height * 0.5), [Target], RGBA);
		}

		customScene.addChild(terrainPrefab.terrain);
		customScene.camera = mainScene.camera;
		brushPreview.reset();

		var tiles = terrainPrefab.terrain.tiles;
		for(i in 0 ... tiles.length){
			var tile = tiles[i];
			var p = new h3d.mat.Pass("overlay");
			p.addShader(new h3d.shader.BaseMesh());
			p.depthTest = LessEqual;
			tile.material.addPass(p);
			var s = new hide.prefab.terrain.CustomUV();
			s.primSize = terrainPrefab.terrain.tileSize;
			s.heightMapSize = terrainPrefab.heightMapResolution;
			s.heightMap = tile.heightMap;
			s.tileIndex = i / 255.0;
			p.addShader(s);
		}

		engine.begin();
		engine.pushTarget(uvTex);
		engine.clear(0,1,0);
		customScene.render(engine);
		engine.popTarget();

		for(tile in tiles)
			tile.material.removePass(tile.material.getPass("overlay"));

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
				copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.substract ? Sub : Add);
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

				copyPass.apply(strokeBuffer.tex, tile.surfaceWeights[currentBrush.index], currentBrush.brushMode.substract ? Sub : Add);
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
				copyPass.apply(strokeBuffer.prevTex, tile.heightMap);
				copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.substract ? Sub : Add);
			}
		}

		for(strokeBuffer in weightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				copyPass.apply(strokeBuffer.prevTex, strokeBuffer.tempTex);
				copyPass.apply(strokeBuffer.tex, strokeBuffer.tempTex, currentBrush.brushMode.substract ? Sub : Add);
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

	public function projectToGround(ray: h3d.col.Ray) {
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

	public function worldToScreen(wx: Float, wy: Float, wz: Float, ctx : Context) {
		var s2d = @:privateAccess ctx.local2d.getScene();
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		var pt = camera.project(wx, wy, wz, s2d.width, s2d.height);
		return new h2d.col.Point(pt.x, pt.y);
	}

	function getBrushWorldPosFromTex(screenPos : h2d.col.Point, ctx : Context) : h3d.Vector {
		var brushWorldPos : h3d.Vector = null;
		if(hxd.Math.floor(screenPos.x * 0.5) >= uvTexPixels.width || hxd.Math.floor(screenPos.y * 0.5) >= uvTexPixels.height) return null;
		var pixel = h3d.Vector.fromColor(uvTexPixels.getPixel( hxd.Math.floor(screenPos.x * 0.5) , hxd.Math.floor(screenPos.y * 0.5)));
		for(i in 0 ... terrainPrefab.terrain.tiles.length)
			if( hxd.Math.ceil(pixel.z * 255) == i)
				brushWorldPos = terrainPrefab.terrain.tiles[i].localToGlobal(new h3d.Vector(pixel.x * terrainPrefab.tileSize, pixel.y * terrainPrefab.tileSize, 0));
		return brushWorldPos;
	}

	function drawBrushPreview( worldPos : h3d.Vector, ctx : Context){
		if(currentBrush.brushMode.mode != Paint && currentBrush.brushMode.mode != Sculpt) return;
		brushPreview.reset();
		var brushWorldPos = uvTexPixels == null ? worldPos : getBrushWorldPosFromTex(worldToScreen(worldPos.x,worldPos.y, worldPos.z, ctx), ctx);
		if(brushWorldPos == null) return;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos, currentBrush.size / 2.0 , false);
		for(i in 0 ... tiles.length){
			var tile = tiles[i];
			var brushPos = tile.globalToLocal(brushWorldPos.clone());
			brushPos.scale3(1.0 / terrainPrefab.tileSize);
			brushPreview.addPreviewMeshAt(tile.tileX, tile.tileY, currentBrush, brushPos);
		}
	}

	function applyBrush(pos, ctx : Context){
		switch (currentBrush.brushMode.mode){
			case Paint: drawSurface(pos, ctx);
			case Sculpt: drawHeight(pos, ctx);
			case Delete: deleteTile(pos, ctx);
		}
	}

	function useBrush( from : h3d.Vector, to : h3d.Vector, ctx : Context){

		if(currentBrush.brushMode.mode == Delete){
			 applyBrush(to, ctx);
			 previewStrokeBuffers();
			 return;
		}

		var dist = (to.sub(from)).length();
		if(dist == 0){
			applyBrush(from, ctx);
			previewStrokeBuffers();
			return;
		}

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
		}else{
			remainingDist += dist;
		}
	}

	public function deleteTile(pos : h3d.Vector, ctx : Context){
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(worldToScreen(pos.x, pos.y, pos.z, ctx), ctx);
		if(brushWorldPos == null) return;
		var tile = terrainPrefab.terrain.getTileAtWorldPos(brushWorldPos);
		if(tile == null) return;
		terrainPrefab.terrain.removeTile(tile);
		tileTrashBin.push(tile);
	}

	public function drawSurface(pos : h3d.Vector, ctx : Context){
		if(currentBrush.index == -1) return;
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(worldToScreen(pos.x, pos.y, pos.z, ctx), ctx);
		if(brushWorldPos == null) return;
		var tiles = terrainPrefab.terrain.getTiles(pos, currentBrush.size / 2.0, autoCreateTile);
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
			currentBrush.bitmap.color = new h3d.Vector(1.0);
			var shader : h3d.shader.pbr.Brush = currentBrush.bitmap.getShader(h3d.shader.pbr.Brush);
			if( shader == null ) shader = currentBrush.bitmap.addShader(new h3d.shader.pbr.Brush());

			shader.normalize = false;
			shader.clamp = false;
			shader.generateIndex = false;
			shader.size = currentBrush.size / terrainPrefab.tileSize;
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / terrainPrefab.tileSize * 0.5), localPos.y - (currentBrush.size  / terrainPrefab.tileSize * 0.5));
			currentBrush.bitmap.blendMode = currentBrush.brushMode.accumulate ? Add : Max;
			shader.strength = currentBrush.strength;
			currentBrush.drawTo(strokeBuffer.tex, localPos, terrainPrefab.tileSize);
		}
	}

	public function drawHeight(pos : h3d.Vector, ctx : Context){
		var brushWorldPos = uvTexPixels == null ? pos : getBrushWorldPosFromTex(worldToScreen(pos.x, pos.y, pos.z, ctx), ctx);
		if(brushWorldPos == null) return;
		var tiles = terrainPrefab.terrain.getTiles(brushWorldPos, currentBrush.size / 2.0, autoCreateTile);
		for(tile in tiles){
			var localPos = tile.globalToLocal(brushWorldPos.clone());
			localPos.scale3(1.0 / terrainPrefab.tileSize);
			var strokeBuffer = heightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if(strokeBuffer.used == false){
				strokeBuffer.prevTex = tile.heightMap;
				tile.heightMap = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}
			currentBrush.bitmap.blendMode = currentBrush.brushMode.accumulate ? Add : Max;
			currentBrush.bitmap.color = new h3d.Vector(currentBrush.strength);
			if(currentBrush.bitmap.getShader(h3d.shader.pbr.Brush) != null ) currentBrush.bitmap.removeShader(currentBrush.bitmap.getShader(h3d.shader.pbr.Brush));
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
				renderTerrainUV(ctx);
			};

			interactive.onPush = function(e) {
				var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();
				var screenPos = new h2d.col.Point(s2d.mouseX, s2d.mouseY);
				if(K.isDown( K.MOUSE_LEFT)){
					e.propagate = false;
					if(currentBrush.isValid()){
						lastPos = worldPos.clone();
						currentBrush.brushMode.substract = K.isDown(K.CTRL);
						useBrush( lastPos, worldPos, ctx);
						previewStrokeBuffers();
						drawBrushPreview(worldPos, ctx);
					}
				}
			};

			interactive.onRelease = function(e) {
				var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();
				var screenPos = new h2d.col.Point(s2d.mouseX, s2d.mouseY);
				remainingDist = 0;
				lastPos = null;
				applyStrokeBuffers();
				resetStrokeBuffers();
				drawBrushPreview(worldPos, ctx);
				checkTrashBin();
			};

			interactive.onMove = function(e) {
				var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();
				var screenPos = new h2d.col.Point(s2d.mouseX, s2d.mouseY);
				if(K.isDown( K.MOUSE_LEFT)){
					e.propagate = false;
					if(currentBrush.isValid()){
						if( lastPos == null) lastPos = worldPos.clone();
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
}