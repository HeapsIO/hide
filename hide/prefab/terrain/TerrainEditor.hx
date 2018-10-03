package hide.prefab.terrain;
using Lambda;
import hxd.Key as K;

class TerrainEditor {

	public var currentBrush : Brush;
	public var currentSurface : h3d.scene.pbr.terrain.Surface;
	public var tmpTexPath : String;
	public var textureType = ["_Albedo", "_Normal", "_MetallicGlossAO"];
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

	public function new(terrainPrefab){
		this.terrainPrefab = terrainPrefab;
		brushPreview = new hide.prefab.terrain.Brush.BrushPreview(terrainPrefab.terrain);
		brushPreview.refreshMesh();
		currentBrush = new Brush();
		copyPass = new h3d.pass.Copy();
		heightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(RGBA32F, terrainPrefab.heightMapResolution + 1);
		weightStrokeBufferArray = new hide.prefab.terrain.StrokeBuffer.StrokeBufferArray(R8, terrainPrefab.weightMapResolution);
	}

	public function update( ?propName : String ) {
		if(propName == "tileSize" || propName == "cellSize"){
			brushPreview.refreshMesh();
		}
		else if(propName == "heightMapResolution" || propName == "weightMapResolution"){
			heightStrokeBufferArray.refresh(terrainPrefab.heightMapResolution + 1);
			weightStrokeBufferArray.refresh(terrainPrefab.weightMapResolution);
		}
	}

	function resetStrokeBuffers(){
		heightStrokeBufferArray.reset();
		weightStrokeBufferArray.reset();
	}

	function applyStrokeBuffers(){
		for(strokeBuffer in heightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.heightMap;
				tile.heightMap = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;
				copyPass.apply(strokeBuffer.tex, tile.heightMap, currentBrush.brushMode.substract ? Sub : Add);
				tile.needNewPixelCapture = true;

				var adjTileX = terrainPrefab.terrain.getTile(tile.tileX - 1, tile.tileY);
				if( adjTileX != null){
					adjTileX.computeEdgesHeight();
				}
				var adjTileY = terrainPrefab.terrain.getTile(tile.tileX, tile.tileY - 1);
				if( adjTileY != null){
					adjTileY.computeEdgesHeight();
				}

				tile.computeNormals();
				tile.computeEdgesNormals();
			}
		}
		terrainPrefab.terrain.refreshTiles();

		for(strokeBuffer in weightStrokeBufferArray.strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrainPrefab.terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				strokeBuffer.tempTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.prevTex;
				strokeBuffer.prevTex = null;
				copyPass.apply(strokeBuffer.tex, tile.surfaceWeights[currentBrush.index], currentBrush.brushMode.substract ? Sub : Add);
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
		if(dist >= 0) { return ray.getPoint(dist); }
		return null;
	}

	function drawBrushPreview( worldPos : h3d.Vector, ctx : Context){
		if(currentBrush.brushMode.mode != Paint && currentBrush.brushMode.mode != Sculpt) return;
		brushPreview.reset();
		var tiles = terrainPrefab.terrain.getTiles(worldPos, currentBrush.size / 2.0 , false);
		for(tile in tiles){
			var brushPos = tile.globalToLocal(worldPos.clone());
			brushPos.scale3(1.0/terrainPrefab.tileSize);
			brushPreview.addPreviewMeshAt(tile.tileX, tile.tileY, currentBrush, brushPos);
		}
	}

	function applyBrush(pos){
		switch (currentBrush.brushMode.mode){
			case Paint: drawSurface(pos);
			case Sculpt: drawHeight(pos);
			case Delete : terrainPrefab.terrain.removeTile(terrainPrefab.terrain.getTileAtWorldPos(pos));
		}
	}

	function useBrush( from : h3d.Vector, to : h3d.Vector, ctx : Context){

		if(currentBrush.brushMode.mode == Delete){
			 applyBrush(to);
			 previewStrokeBuffers();
			 return;
		}

		var dist = (to.sub(from)).length();
		if(dist == 0){
			applyBrush(from);
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

				applyBrush(pos);

				dist -= currentBrush.step - remainingDist;
				remainingDist = 0;
			}
			remainingDist = dist;
			previewStrokeBuffers();
		}else{
			remainingDist += dist;
		}
	}

	public function drawSurface(pos : h3d.Vector){
		if(currentBrush.index == -1) return;
		var tiles = terrainPrefab.terrain.getTiles(pos, currentBrush.size / 2.0 , true);
		for(tile in tiles){

			var strokeBuffer = weightStrokeBufferArray.getStrokeBuffer(tile.tileX, tile.tileY);
			if(strokeBuffer.used == false){
				strokeBuffer.prevTex = tile.surfaceWeights[currentBrush.index];
				tile.surfaceWeights[currentBrush.index] = strokeBuffer.tempTex;
				strokeBuffer.used = true;
			}

			var localPos = tile.globalToLocal(pos.clone());
			localPos.scale3(1.0 / terrainPrefab.tileSize);
			currentBrush.bitmap.color = new h3d.Vector(1.0);
			var shader : h3d.shader.pbr.Brush = currentBrush.bitmap.getShader(h3d.shader.pbr.Brush);
			if( shader == null ) shader = currentBrush.bitmap.addShader(new h3d.shader.pbr.Brush());

			// Add/Sub the current brush on the weightMap
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

	public function drawHeight(pos : h3d.Vector){
		var tiles = terrainPrefab.terrain.getTiles(pos, currentBrush.size / 2.0 + 5, true);
		for(tile in tiles){
			var localPos = tile.globalToLocal(pos.clone());
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

			interactive.onPush = function(e) {
				if(K.isDown( K.MOUSE_LEFT)){
					e.propagate = false;
					if(currentBrush.isValid()){
						var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();
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
				remainingDist = 0;
				lastPos = null;
				applyStrokeBuffers();
				resetStrokeBuffers();
				drawBrushPreview(worldPos, ctx);
			};

			interactive.onMove = function(e) {
				var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();

				/*var camera = @:privateAccess ctx.local3d.getScene().camera;
				var ray = camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
				for(tile in terrain.tiles){
					var pixels = tile.heightMap.capturePixels();
				}*/

				if(K.isDown( K.MOUSE_LEFT)){
					e.propagate = false;
					if(currentBrush.isValid()){
						if( lastPos == null) lastPos = worldPos.clone();
						useBrush( lastPos, worldPos, ctx);
						lastPos = worldPos;
					}
				}
				drawBrushPreview(worldPos, ctx);
			};
		}
		else{
			if(interactive != null) interactive.remove();
			brushPreview.reset();
		}
	}
}