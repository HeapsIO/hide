package hide.prefab;
using Lambda;
import hxd.Key as K;

#if editor

class BrushMode {
	public var accumulate = false;
	public var substract = false;
	public var sculptMode = false;

	public function new(){}
}

class StrokeBuffer {
	public var tex : h3d.mat.Texture;
	public var x : Int;
	public var y : Int;
	public var used : Bool;
	public var prevTex : h3d.mat.Texture;
	public var tempTex : h3d.mat.Texture;

	public function new(size, x, y){
		tex = new h3d.mat.Texture(size,size, [Target], R16F);
		tempTex = new h3d.mat.Texture(size,size, [Target], R16F);
		tex.filter = Nearest;
		tempTex.filter = Nearest;
		this.x = x;
		this.y = y;
		used = false;
	}

	public function linkTo(tile : h3d.scene.pbr.Terrain.Tile){
		prevTex = tile.heightMap;
		tile.heightMap = tempTex;
		used = true;
	}
}

class TilePreview extends h3d.scene.Mesh {
	public var used = false;
	public var heightMap : h3d.mat.Texture;
	public var shader : hide.prefab.terrain.TilePreview;

	public function new(prim, parent){
		super(prim, null, parent);
		material.setDefaultProps("ui");
		material.shadows = false;
		material.blendMode = Alpha;
		material.color = new h3d.Vector(1,0,0,0.5);
		shader = new hide.prefab.terrain.TilePreview();
		material.mainPass.addShader(shader);
	}

	override function sync(ctx : h3d.impl.RenderContext) {
		shader.heightMap = heightMap;
		shader.heightMapSize = heightMap.width;
		shader.primSize = Std.instance(parent, h3d.scene.pbr.Terrain).tileSize;
	}
}

class BrushPreview {

	var terrain : h3d.scene.pbr.Terrain;
	var tiles : Array<TilePreview> = [];

	public function new(terrain){
		this.terrain = terrain;
	}

	public function addPreviewMeshAt(x : Int, y : Int, brush : Brush, brushPos : h3d.Vector) : TilePreview {
		var tilePreview = null;
		for(tile in tiles){
			if(tile.used) continue;
			tilePreview = tile;
		}
		if(tilePreview == null){
			tilePreview = new TilePreview(terrain.grid, terrain);
			tiles.push(tilePreview);
		}
		tilePreview.used = true;
		tilePreview.heightMap = terrain.getTile(x,y).heightMap;
		var pos = new h3d.Vector(x * terrain.tileSize, y * terrain.tileSize);
		tilePreview.setPosition(pos.x, pos.y, pos.z + 0.1 * terrain.scaleZ);
		tilePreview.visible = true;
		tilePreview.shader.brushTex = brush.tex;
		tilePreview.shader.brushSize =  brush.size;
		tilePreview.shader.brushPos = brushPos;
		return tilePreview;
	}
	public function reset(){
		for(tile in tiles){
			tile.used = false;
			tile.visible = false;
		}
	}

	public function refreshMesh(){
		for(tile in tiles)
			tile.primitive = terrain.grid;
	}
}

class Brush {
	public var name : String;
	public var size : Float;
	public var strength : Float;
	public var step : Float;
	public var tex : h3d.mat.Texture;
	public var bitmap : h2d.Bitmap;
	public var texPath : String;
	public var index : Int = -1;

	public function new(){

	}

	public function isValid() : Bool{
		return ( bitmap != null && tex != null && name != null && step > 0.0 && texPath != null);
	}

	public function scaleForTex(tileSize : Float, texResolution : Float){
		var scale = size / ((tileSize / texResolution) * tex.width);
		bitmap.setScale(scale);
	}

	public function drawTo( target : h3d.mat.Texture, pos : h3d.Vector, tileSize : Float, ?offset = 0){
		var texSize = target.width + offset;
		scaleForTex(tileSize, texSize);
		bitmap.setPosition(
						(pos.x * texSize - ( size / (tileSize / texSize) * 0.5 )),
						(pos.y * texSize - ( size / (tileSize / texSize) * 0.5 )));
		bitmap.drawTo(target);
	}
}

typedef SurfaceProps = {
	albedo : String,
	normal : String,
	pbr : String,
	tilling : Float,
	angle : Float,
	offsetX : Float,
	offsetY : Float
};

class Terrain extends Object3D {

	public var tileSize = 1;
	public var cellSize = 1;
	public var heightMapResolution : Int = 1;
	public var weightMapResolution : Int = 1;

	var tmpSurfacesProps : Array<SurfaceProps> = [];
	var terrain : h3d.scene.pbr.Terrain;

	#if editor
	var brushPreview : BrushPreview;
	var interactive : h2d.Interactive;
	var currentBrush : Brush;
	var currentSurface : h3d.scene.pbr.Terrain.Surface;
	var brushMode : BrushMode;
	var remainingDist = 0.0;
	var previewResolution = 256;
	var lastPos : h3d.Vector;
	var grid : h3d.scene.Graphics;
	var showGrid : Bool;
	var copyPass : h3d.pass.Copy;
	var strokeBuffers : Array<StrokeBuffer> = [];
	var tmpTexPath : String;
	var textureType = ["_Albedo", "_Normal", "_MetallicGlossAO"];
	#end

	override function load( obj : Dynamic ) {
		super.load(obj);
		tileSize = obj.tileSize == null ? 1 : obj.tileSize;
		cellSize = obj.cellSize == null ? 1 : obj.cellSize;
		heightMapResolution = obj.heightMapResolution == null ? 1 : hxd.Math.ceil(obj.heightMapResolution);
		weightMapResolution = obj.weightMapResolution == null ? 1 : hxd.Math.ceil(obj.weightMapResolution);
		if( obj.surfaces!= null ) tmpSurfacesProps = obj.surfaces;
	}

	override function save() {
		var obj : Dynamic = super.save();
		if( tileSize > 0 ) obj.tileSize = tileSize;
		if( cellSize > 0 ) obj.cellSize = cellSize;
		if( heightMapResolution > 0 ) obj.heightMapResolution = hxd.Math.ceil(heightMapResolution);
		if( weightMapResolution > 0 ) obj.weightMapResolution = hxd.Math.ceil(weightMapResolution);

		var surfacesProps : Array<SurfaceProps> = [];
		for(surface in terrain.surfaces){
			var surfaceProps : SurfaceProps =
			{
				albedo : surface.albedo.name,
				normal : surface.normal.name,
				pbr : surface.pbr.name,
				tilling : surface.tilling,
				angle : surface.angle,
				offsetX : surface.offset.x,
				offsetY : surface.offset.y
			};
			surfacesProps.push(surfaceProps);
		}
		obj.surfaces = surfacesProps;

		return obj;
	}

	function saveHeightTextures(ctx : Context){
		if(ctx.shared.currentPath == null) return;
		var dir = ctx.shared.currentPath.split(".l3d")[0] + "_terrain";
		for(tile in terrain.tiles){
			var pixels = tile.heightMap.capturePixels();
			var name = tile.tileX + "_" + tile.tileY + "_" + "h";
			ctx.shared.saveTexture(name, pixels.bytes, dir, "heightMap");
		}
	}

	function saveWeightTextures(ctx : Context){
		if(ctx.shared.currentPath == null) return;
		var dir = ctx.shared.currentPath.split(".l3d")[0] + "_terrain";
		for(tile in terrain.tiles){
			var surfaceIndex = 0;
			for(surfaceWeight in tile.surfaceWeights){
				var pixels = surfaceWeight.capturePixels();
				var bytes = pixels.toPNG();
				var name = tile.tileX + "_" + tile.tileY + "_" + surfaceIndex + "_" + "w";
				ctx.shared.saveTexture(name, bytes, dir, "png");
				surfaceIndex++;
			}
		}
	}

	function loadHeightTextures(ctx : Context){
		var dir = ctx.shared.currentPath.split(".l3d")[0] + "_terrain";
		var files = sys.FileSystem.readDirectory(hide.Ide.inst.getPath(dir));
		for(file in files){
			var texName = file.split(".heightMap")[0];
			var coords = texName.split("_");
			if(coords[2] != "h") continue;
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			var bytes = ctx.shared.loadBytes(dir + "/" + file);
			if(bytes == null) continue;
			var pixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(heightMapResolution + 2, heightMapResolution + 2, bytes, RGBA32F);
			var tile = terrain.createTile(x, y);
			tile.heightMap.uploadPixels(pixels);
		}
	}

	function loadWeightTextures(ctx : Context){
		var dir = ctx.shared.currentPath.split(".l3d")[0] + "_terrain";
		var files = sys.FileSystem.readDirectory(hide.Ide.inst.getPath(dir)); // TODO : FIXME
		for(file in files){
			var texName = file.split(".png")[0];
			var coords = texName.split("_");
			if(coords[3] != "w") continue;
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			var i = Std.parseInt(coords[2]);
			var tile = terrain.createTile(x, y);
			var tex = ctx.loadTexture(dir + "/" + file);
			function wait() {
				if( tex.flags.has(Loading) )
					haxe.Timer.delay(wait, 1);
				else {
					tile.uploadWeightMap(tex, i);
					tex.dispose();
				}
			}
			wait();
		}
	}

	function initTexture(ctx : Context, path : String, ?wrap : h3d.mat.Data.Wrap) : h3d.mat.Texture {
		if(path != null){
			var tex = ctx.shared.loadTexture(hide.Ide.inst.getPath(path));
			function wait() {
				if( tex.flags.has(Loading) )
					haxe.Timer.delay(wait, 1);
			}
			wait();
			if(tex != null ) tex.wrap = wrap == null ? Repeat : wrap;
			return tex;
		}
		return null;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		terrain = new h3d.scene.pbr.Terrain(ctx.local3d);
		terrain.cellCount = getCellCount();
		terrain.cellSize = getCellSize();
		terrain.tileSize = terrain.cellCount * terrain.cellSize;
		terrain.refreshMesh();
		terrain.heightMapResolution = heightMapResolution;
		terrain.weightMapResolution = weightMapResolution;

		ctx.local3d = terrain;
		ctx.local3d.name = name;

		for(surfaceProps in tmpSurfacesProps){
			var surface = terrain.addEmptySurface();
			var albedo = ctx.shared.loadTexture(hide.Ide.inst.getPath(surfaceProps.albedo));
			var normal = ctx.shared.loadTexture(hide.Ide.inst.getPath(surfaceProps.normal));
			var pbr = ctx.shared.loadTexture(hide.Ide.inst.getPath(surfaceProps.pbr));
			function wait() {
				if( albedo.flags.has(Loading) || normal.flags.has(Loading)|| pbr.flags.has(Loading))
					haxe.Timer.delay(wait, 1);
				else{
					surface.albedo = albedo;
					surface.normal = normal;
					surface.pbr = pbr;
					surface.offset.x = surfaceProps.offsetX;
					surface.offset.y = surfaceProps.offsetY;
					surface.angle = surfaceProps.angle;
					surface.tilling = surfaceProps.tilling;
					albedo.dispose();
					normal.dispose();
					pbr.dispose();
				}
			}
			wait();
		}

		function waitAll() {
			var ready = true;
			for(surface in terrain.surfaces)
				if(surface == null || surface.albedo == null || surface.normal == null || surface.pbr == null ){
					ready = false;
					break;
				}
			if(ready){
				terrain.generateSurfaceArray();
				loadWeightTextures(ctx);
				loadHeightTextures(ctx);
			}
			else
				haxe.Timer.delay(waitAll, 1);
		}
		waitAll();

		#if editor
		brushPreview = new BrushPreview(terrain);
		brushPreview.refreshMesh();
		currentBrush = new Brush();
		brushMode = new BrushMode();
		copyPass = new h3d.pass.Copy();
		#end

		updateInstance(ctx);

		return ctx;
	}

	function getCellCount(){
		var resolution = Math.max(0.1, cellSize);
		var cellCount = Math.ceil(Math.min(1000, tileSize / resolution));
		return cellCount;
	}

	function getCellSize(){
		var cellCount = getCellCount();
		var finalCellSize = tileSize / cellCount;
		return finalCellSize;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);

		#if editor
		if(propName == "currentSurface.tilling"
		|| propName == "currentSurface.offset.x"
		|| propName == "currentSurface.offset.y"
		|| propName == "currentSurface.angle"
		|| propName == "currentSurface.parallaxAmount")
			terrain.updateSurfaceParams();

		if(propName == "tileSize" || propName == "cellSize"){
			terrain.cellCount = getCellCount();
			terrain.cellSize = getCellSize();
			terrain.tileSize = terrain.cellCount * terrain.cellSize;
			terrain.refreshMesh();
			brushPreview.refreshMesh();
		}

		if(propName == "heightMapResolution" || propName == "weightMapResolution"){
			terrain.heightMapResolution = heightMapResolution;
			terrain.weightMapResolution = weightMapResolution;
			terrain.refreshTex();
			updateStrokeBuffers(heightMapResolution + 2);
		}
		#end
	}

	#if editor

	function getStrokeBuffer(x, y){
		for(strokebuffer in strokeBuffers)
			if((strokebuffer.x == x && strokebuffer.y == y) || strokebuffer.used == false){
				strokebuffer.x = x;
				strokebuffer.y = y;
				return strokebuffer;
			}
		var strokeBuffer = new StrokeBuffer(heightMapResolution + 2, x, y);
		strokeBuffers.push(strokeBuffer);
		return strokeBuffer;
	}

	function updateStrokeBuffers(size){
		for(strokeBuffer in strokeBuffers){
			if(strokeBuffer.tex != null) strokeBuffer.tex.dispose();
			if(strokeBuffer.tempTex != null) strokeBuffer.tempTex.dispose();
			strokeBuffer.tex = new h3d.mat.Texture(size,size, [Target], R16F);
			strokeBuffer.tempTex = new h3d.mat.Texture(size,size, [Target], R16F);
			strokeBuffer.tex.filter = Nearest;
			strokeBuffer.tempTex.filter = Nearest;
		}
	}

	function resetStrokeBuffers(){
		for(strokeBuffer in strokeBuffers){
			strokeBuffer.used = false;
			strokeBuffer.tex.clear(0);
			strokeBuffer.tempTex.clear(0);
		}
	}

	function applyStrokeBuffers(){
		for(strokeBuffer in strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				copyPass.apply(strokeBuffer.tex, strokeBuffer.prevTex, brushMode.substract ? Sub : Add);
				strokeBuffer.tempTex = tile.heightMap;
				tile.heightMap = strokeBuffer.prevTex;
			}
		}
	}

	function previewStrokeBuffers(){
		for(strokeBuffer in strokeBuffers){
			if(strokeBuffer.used == true){
				var tile = terrain.getTile(strokeBuffer.x, strokeBuffer.y);
				copyPass.apply(strokeBuffer.prevTex, tile.heightMap);
				copyPass.apply(strokeBuffer.tex, tile.heightMap, brushMode.substract ? Sub : Add);
			}
		}
	}

	public function projectToGround(ray: h3d.col.Ray) {
		var minDist = -1.;
		var normal = terrain.getAbsPos().up();
		var plane = h3d.col.Plane.fromNormalPoint(normal.toPoint(), new h3d.col.Point(terrain.getAbsPos().tx, terrain.getAbsPos().ty, terrain.getAbsPos().tz));
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
		brushPreview.reset();
		var tiles = terrain.getTiles(worldPos, currentBrush.size / 2.0 , false);
		for(tile in tiles){
			var brushPos = tile.globalToLocal(worldPos.clone());
			brushPos.scale3(1.0/terrain.tileSize);
			brushPreview.addPreviewMeshAt(tile.tileX, tile.tileY, currentBrush, brushPos);
		}
	}

	function drawBrush( from : h3d.Vector, to : h3d.Vector, ctx : Context){
		var dist = (to.sub(from)).length();
		if(dist == 0){
			if(brushMode.sculptMode) drawHeight(currentBrush, from);
			else drawSurface(currentBrush, from);
			return;
		}
		else if(dist + remainingDist >= currentBrush.step){
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

				if(brushMode.sculptMode) drawHeight(currentBrush, pos);
				else drawSurface(currentBrush, pos);

				dist -= currentBrush.step - remainingDist;
				remainingDist = 0;
			}
			remainingDist = dist;
		}else{
			remainingDist += dist;
		}
	}

	public function drawSurface(brush : Brush, pos : h3d.Vector){
		if(currentBrush.index == -1) return;
		var tiles = terrain.getTiles(pos, currentBrush.size / 2.0 , true);
		for(tile in tiles){
			var localPos = tile.globalToLocal(pos.clone());
			localPos.scale3(1.0/tileSize);
			currentBrush.bitmap.color = new h3d.Vector(1);
			var shader : h3d.shader.pbr.Brush = currentBrush.bitmap.getShader(h3d.shader.pbr.Brush);
			if( shader == null ) shader = currentBrush.bitmap.addShader(new h3d.shader.pbr.Brush());
			shader.normalize = false;

			currentBrush.bitmap.blendMode = brushMode.substract ? Sub : Add ;
			shader.strength = currentBrush.strength;
			currentBrush.drawTo(tile.surfaceWeights[currentBrush.index], localPos, tileSize);
			tile.generateWeightArray();

			shader.normalize = true;
			currentBrush.bitmap.blendMode = None;
			shader.refIndex = currentBrush.index;
			shader.weightTextures = tile.surfaceWeightArray;
			shader.weightCount = tile.surfaceCount;
			shader.size = currentBrush.size / tileSize;
			shader.pos = new h3d.Vector(localPos.x - (currentBrush.size  / tileSize * 0.5), localPos.y - (currentBrush.size  / tileSize * 0.5));
			for(i in 0 ... tile.surfaceWeights.length){
				if(i == currentBrush.index) continue;
				shader.targetIndex = i;
				currentBrush.drawTo(tile.surfaceWeights[i], localPos, tileSize);
			}
			tile.generateWeightArray();
		}
	}

	public function drawHeight(brush : Brush, pos : h3d.Vector){
		var tiles = terrain.getTiles(pos, currentBrush.size / 2.0 + 5, true);
		for(tile in tiles){
			var localPos = tile.globalToLocal(pos.clone());
			localPos.scale3(1.0/tileSize);
			var strokeBuffer = getStrokeBuffer(tile.tileX, tile.tileY);
			if(strokeBuffer.used == false) strokeBuffer.linkTo(tile);
			currentBrush.bitmap.blendMode = brushMode.accumulate ? Add : Max;
			currentBrush.bitmap.color = new h3d.Vector(currentBrush.strength);
			if(currentBrush.bitmap.getShader(h3d.shader.pbr.Brush) != null ) currentBrush.bitmap.removeShader(currentBrush.bitmap.getShader(h3d.shader.pbr.Brush));
			currentBrush.drawTo(strokeBuffer.tex, localPos, tileSize, -2);
		}
	}

	override function setSelected( ctx : Context, b : Bool ) {
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
						brushMode.substract = K.isDown(K.CTRL);
						drawBrush( lastPos, worldPos, ctx);
						previewStrokeBuffers();
					}
				}
			};

			interactive.onRelease = function(e) {
				remainingDist = 0;
				lastPos = null;
				applyStrokeBuffers();
				resetStrokeBuffers();
			};

			interactive.onMove = function(e) {
				var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, ctx).toVector();
				if(K.isDown( K.MOUSE_LEFT)){
					e.propagate = false;
					if(currentBrush.isValid()){
						if( lastPos == null) lastPos = worldPos.clone();
						drawBrush( lastPos, worldPos, ctx);
						lastPos = worldPos;
					}
				}
				previewStrokeBuffers();
				drawBrushPreview(worldPos, ctx);
			};
		}
		else{
			if(interactive != null) interactive.remove();
			brushPreview.reset();
		}
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "terrain" };
	}

	override function edit( ctx : EditContext ) {

		//super.edit(ctx);

		function loadTexture( ctx : hide.prefab.EditContext, propsName : String, ?wrap : h3d.mat.Data.Wrap){
			var texture = ctx.rootContext.shared.loadTexture(propsName);
			texture.wrap = wrap == null ? Repeat : wrap;
			return texture;
		}

		var props = new hide.Element('
			<div class="group" name="<Terrain>">
				<dl>
					<dt>Tile Size</dt><dd><input type="range" min="1" max="100" value="0" field="tileSize"/></dd>
					<dt>Cell Size</dt><dd><input type="range" min="0.01" max="10" value="0" field="cellSize"/></dd>
					<dt>WeightMap Resolution</dt><dd><input type="range" min="1" max="1000" value="0" step="1" field="weightMapResolution"/></dd>
					<dt>HeightMap Resolution</dt><dd><input type="range" min="1" max="1000" value="0" step="1" field="heightMapResolution"/></dd>
					<dt>HeightBlend</dt><dd><input type="checkbox" field="terrain.useHeightBlend"/></dd>
					<dt>Parallax Amount</dt><dd><input type="range" min="0" max="1" field="terrain.parallaxAmount"/></dd>
					<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
			<div class="group" name="Mode">
				<dt>Accumulate</dt><dd><input type="checkbox" field="brushMode.accumulate"/></dd>
				<dt>Scrulpt</dt><dd><input type="checkbox" field="brushMode.sculptMode"/></dd>
			</div>
			<div class="group" name="Brush">
				<dl>
					<div class="terrain-brushes"></div>
					<dt>Size</dt><dd><input type="range" min="0.01" max="10" field="currentBrush.size"/></dd>
					<dt>Strength</dt><dd><input type="range" min="0" max="1" field="currentBrush.strength"/></dd>
					<dt>Step</dt><dd><input type="range" min="0.01" max="10" field="currentBrush.step"/></dd>
				</dl>
			</div>
			<div class="group" name="Surface">
				<dt>Add</dt><dd><input type="texturepath" field="tmpTexPath"/></dd>
				<div class="terrain-surfaces"></div>
				<dt>Tilling</dt><dd><input type="range" min="0" max="10" field="currentSurface.tilling"/></dd>
				<dt>Offset X</dt><dd><input type="range" min="0" max="1" field="currentSurface.offset.x"/></dd>
				<dt>Offset Y</dt><dd><input type="range" min="0" max="1" field="currentSurface.offset.y"/></dd>
				<dt>Rotate</dt><dd><input type="range" min="0" max="360" field="currentSurface.angle"/></dd>
			</div>
			<div><dl><input type="button" value="Save" class="save"/><dl></div>
		');

		props.find(".save").click(function(_) {
			saveWeightTextures(ctx.rootContext);
			saveHeightTextures(ctx.rootContext);
		});

		inline function setRange(name, value){
			var field = Lambda.find(ctx.properties.fields, f->f.fname==name);
			if(field != null) @:privateAccess field.range.value = value;
		};

		var brushes : Array<Dynamic> = ctx.scene.config.get("terrain.brushes");
		var brushesContainer = props.find(".terrain-brushes");
		function refreshBrushes(){
			brushesContainer.empty();
			for( brush in brushes){
				var label = brush.name + "<br/>Step : " + brush.step + "<br/>Strength : " + brush.strength + "<br/>Size : " + brush.size ;
				var img : Element;
				if( brush.name == currentBrush.name) img = new Element('<div class="brush-preview-selected"></div>');
				else img = new Element('<div class="brush-preview"></div>');
				img.css("background-image", 'url("file://${hide.Ide.inst.getPath(brush.texture)}")');
				var brushElem = new Element('<div class="brush"><span class="tooltiptext">$label</span></div>').prepend(img);
				brushElem.click(function(e){
					currentBrush.size = brush.size;
					currentBrush.strength = brush.strength;
					currentBrush.step = brush.step;
					currentBrush.texPath = hide.Ide.inst.getPath(brush.texture);
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
				setRange("currentBrush.size", currentBrush.size);
				setRange("currentBrush.strength", currentBrush.strength);
				setRange("currentBrush.step", currentBrush.step);
			}
		}
		refreshBrushes();

		var surfacesContainer = props.find(".terrain-surfaces");
		function refreshSurfaces(){
			surfacesContainer.empty();
			for( i in 0 ... terrain.surfaces.length ){
				var surface = terrain.surfaces[i];
				if(surface == null || surface.albedo == null) continue;
				var label = surface.albedo.name;
				var img : Element;
				if( i == currentBrush.index) img = new Element('<div class="surface-preview-selected"></div>');
				else img = new Element('<div class="surface-preview"></div>');
				var imgPath = hide.Ide.inst.getPath(surface.albedo.name);
				img.css("background-image", 'url("file://$imgPath")');
				var surfaceElem = new Element('<div class=" surface"><span class="tooltiptext">$label</span></div>').prepend(img);
				surfaceElem.click(function(e){
					currentBrush.index = i;
					currentSurface = terrain.getSurface(i);
					refreshSurfaces();
				});
				surfacesContainer.append(surfaceElem);
			}
			if(currentSurface != null){
				setRange("currentSurface.tilling", currentSurface.tilling);
				setRange("currentSurface.offset.x", currentSurface.offset.x);
				setRange("currentSurface.offset.y", currentSurface.offset.y);
				setRange("currentSurface.angle", currentSurface.angle);
			}
		};
		refreshSurfaces();

		ctx.properties.add(props, this, function(pname) {
			if(pname == "tmpTexPath"){
				var split : Array<String> = [];
				var curTypeIndex = 0;
				while( split.length <= 1 && curTypeIndex < textureType.length){
					split = tmpTexPath.split(textureType[curTypeIndex]);
					curTypeIndex++;
				}
				if(split.length > 1) {
					var t : h3d.mat.Texture;
					var name = split[0];
					var albedo = ctx.rootContext.shared.loadTexture(name + textureType[0] + ".png");
					var normal = ctx.rootContext.shared.loadTexture(name + textureType[1] + ".png");
					var pbr = ctx.rootContext.shared.loadTexture(name + textureType[2] + ".png");
					function wait() {
						if( albedo.flags.has(Loading) || normal.flags.has(Loading)|| pbr.flags.has(Loading))
							haxe.Timer.delay(wait, 1);
						else{
							if(terrain.getSurfaceFromTex(name + textureType[0] + ".png", name + textureType[1] + ".png", name + textureType[2] + ".png") == null){
								terrain.addSurface(albedo, normal, pbr);
								albedo.dispose();
								normal.dispose();
								pbr.dispose();
								terrain.generateSurfaceArray();
								props.remove();
								edit(ctx);
							}
						}
					}
					wait();
				}
			}
			tmpTexPath = null;

		ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = hxd.prefab.Library.register("Terrain", Terrain);
}

#end