package hide.prefab;
using Lambda;
import hxd.Key as K;

class BrushMode {
	public var accumulate = false;
	public var substract = false;
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

class Brush {
	public var name : String;
	public var size : Float;
	public var strength : Float;
	public var step : Float;
	public var tex : h3d.mat.Texture;
	public var bitmap : h2d.Bitmap;
	public var texPath : String;

	public function new(){

	}

	public function isValid() : Bool{
		return ( bitmap != null && tex != null && name != null && step > 0.0 && texPath != null);
	}

	public function scaleForTex(tileSize : Float, texResolution : Float){
		var scale = size / ((tileSize / texResolution) * tex.width);
		bitmap.setScale(scale);
	}

	public function drawTo( target : h3d.mat.Texture, pos : h3d.Vector, tileSize : Float){
		var texSize = target.width - 2;
		scaleForTex(tileSize, texSize);
		bitmap.setPosition(
						(pos.x * texSize - ( size / (tileSize / texSize) * 0.5 )),
						(pos.y * texSize - ( size / (tileSize / texSize) * 0.5 )));
		bitmap.drawTo(target);
	}
}

class Terrain extends Object3D {

	public var tileSize = 1;
	public var cellSize = 1;
	public var heightMapResolution = 1;
	public var weightMapResolution = 1;

	var terrain : h3d.scene.pbr.Terrain;

	#if editor
	var interactive : h2d.Interactive;
	var currentBrush : Brush;
	var substractMode = false;
	var remainingDist = 0.0;
	var previewResolution = 256;
	var accumulate : Bool;
	var lastPos : h3d.Vector;

	var grid : h3d.scene.Graphics;
	var showGrid : Bool;
	var currentSurfaceName: String;
	var copyPass : h3d.pass.Copy;
	var strokeBuffers : Array<StrokeBuffer> = [];
	#end

	override function load( obj : Dynamic ) {
		super.load(obj);
		tileSize = obj.tileSize == null ? 1 : obj.tileSize;
		cellSize = obj.cellSize == null ? 1 : obj.cellSize;
		heightMapResolution = obj.heightMapResolution == null ? 1 : obj.heightMapResolution;
		weightMapResolution = obj.weightMapResolution == null ? 1 : obj.weightMapResolution;
	}

	override function save() {
		var o : Dynamic = super.save();
		if( tileSize > 0 ) o.tileSize = tileSize;
		if( cellSize > 0 ) o.cellSize = cellSize;
		if( heightMapResolution > 0 ) o.heightMapResolution = heightMapResolution;
		if( weightMapResolution > 0 ) o.weightMapResolution = weightMapResolution;
		return o;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		terrain = new h3d.scene.pbr.Terrain(ctx.local3d);
		terrain.cellSize = getCellSize();
		terrain.tileSize = tileSize;
		terrain.heightMapResolution = heightMapResolution;
		terrain.weightMapResolution = weightMapResolution;
		terrain.createTile(0,0);
		terrain.refresh();


		ctx.local3d = terrain;
		ctx.local3d.name = name;

		#if editor
		currentBrush = new Brush();
		copyPass = new h3d.pass.Copy();
		#end

		updateInstance(ctx);

		return ctx;
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
				copyPass.apply(strokeBuffer.tex, strokeBuffer.prevTex, substractMode ? Sub : Add);
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
				copyPass.apply(strokeBuffer.tex, tile.heightMap, substractMode ? Sub : Add);
			}
		}
	}
	#end

	function getCellSize(){
		var resolution = Math.max(0.1, cellSize);
		var cellCount = Math.ceil(Math.min(100, tileSize / resolution));
		var finalCellSize = 1.0 / cellCount * tileSize;
		return finalCellSize;
	}

	function checkTexture(tex : h3d.mat.Texture, size, format) : h3d.mat.Texture {
		if(tex == null || tex.width != size || tex.height != size || tex.format != format){
			if(tex != null) tex.dispose();
			return new h3d.mat.Texture(size, size, [Target], format);
		}
		return tex;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);

		if(propName == "tileSize" || propName == "cellSize"){
			terrain.cellSize = getCellSize();
			terrain.tileSize = tileSize;
			terrain.refreshMesh();
		}

		#if editor

		if(propName == "heightMapResolution" || propName == "weightMapResolution"){
			terrain.heightMapResolution = heightMapResolution;
			terrain.weightMapResolution = weightMapResolution;
			terrain.refreshTex();
			updateStrokeBuffers(heightMapResolution+2);
		}

		if(currentBrush.isValid())
			currentBrush.bitmap.color = new h3d.Vector(currentBrush.strength);

		#end
	}

	#if editor

	public function projectToGround(ray: h3d.col.Ray, z) {
		var minDist = -1.;
		var zPlane = h3d.col.Plane.Z(z);
		var pt = ray.intersect(zPlane);
		if(pt != null) { minDist = pt.sub(ray.getPos()).length();}
		return minDist;
	}

	function screenToWorld( u : Float, v : Float, z, ctx : Context) {
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		var ray = camera.rayFromScreen(u, v);
		var dist = projectToGround(ray, z);
		if(dist >= 0) { return ray.getPoint(dist); }
		return null;
	}

	function drawBrushPreview( coords : h3d.Vector, ctx : Context){
		/*currentBrush.bitmap.blendMode = Add;
		currentBrush.scaleForTex(terrain.tileSize, previewResolution);
		currentBrush.bitmap.setPosition(coords.x * previewResolution - (currentBrush.size / (tileSize/previewResolution))* 0.5, coords.y * previewResolution - (currentBrush.size / (tileSize/previewResolution))* 0.5);
		currentBrush.bitmap.drawTo(brushPreview);*/
	}

	function drawBrush( from : h3d.Vector, to : h3d.Vector, ctx : Context){

		var dist = (to.sub(from)).length();
		if(dist == 0){
			var tiles = terrain.getTiles(from, currentBrush.size / 2.0 +1, true);
			for(tile in tiles){
					var strokeBuffer = getStrokeBuffer(tile.tileX, tile.tileY);
					if(strokeBuffer.used == false) strokeBuffer.linkTo(tile);
					var localPos = tile.globalToLocal(from.clone());
					localPos.scale3(1/tileSize);
					currentBrush.drawTo(strokeBuffer.tex, localPos, tileSize);
				}
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

				var tiles = terrain.getTiles(pos, currentBrush.size / 2.0 + 1.0 / tileSize, true);

				for(tile in tiles){
					var strokeBuffer = getStrokeBuffer(tile.tileX, tile.tileY);
					if(strokeBuffer.used == false) strokeBuffer.linkTo(tile);
					var localPos = tile.globalToLocal(pos.clone());
					localPos.scale3(1/tileSize);
					currentBrush.drawTo(strokeBuffer.tex, localPos, tileSize);
				}
				dist -= currentBrush.step - remainingDist;
				remainingDist = 0;
			}
			remainingDist = dist;
		}else{
			remainingDist += dist;
		}
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if(b){
			var s2d = @:privateAccess ctx.local2d.getScene();
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = false;

			interactive.onPush = function(e) {
				if(K.isDown( K.MOUSE_LEFT)){
					if(currentBrush.isValid()){
						var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, terrain.getAbsPos().tz, ctx).toVector();
						lastPos = worldPos.clone();
						substractMode = K.isDown(K.CTRL);
						currentBrush.bitmap.blendMode = accumulate ? Add : Max;
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
				if(K.isDown( K.MOUSE_LEFT)){
					if(currentBrush.isValid()){
						var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY, terrain.getAbsPos().tz, ctx).toVector();
						if( lastPos == null) lastPos = worldPos.clone();
						drawBrush( lastPos, worldPos, ctx);
						lastPos = worldPos;
					}
				}
				previewStrokeBuffers();
			};

		}
		else{
			if(interactive != null) interactive.remove();
		}
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "terrain" };
	}

	override function edit( ctx : EditContext ) {
		function loadTexture( ctx : hide.prefab.EditContext, propsName : String, ?wrap : h3d.mat.Data.Wrap){
			var texture = ctx.rootContext.loadTexture(propsName);
			texture.wrap = wrap == null ? Repeat : wrap;
			return texture;
		}
		var props = new hide.Element('
			<div class="group" name="Position">
				<dt>X</dt><dd><input type="range" min="-10" max="10" value="0" field="x"/></dd>
				<dt>Y</dt><dd><input type="range" min="-10" max="10" value="0" field="y"/></dd>
				<dt>Z</dt><dd><input type="range" min="-10" max="10" value="0" field="z"/></dd>
			</div>
			<div class="group" name="<Terrain>">
				<dl>
					<dt>Tile Size</dt><dd><input type="range" min="1" max="100" value="0" field="tileSize"/></dd>
					<dt>Cell Size</dt><dd><input type="range" min="0.01" max="10" value="0" field="cellSize"/></dd>
					<dt>WeightMap Resolution</dt><dd><input type="range" min="1" max="4096" value="0" field="weightMapResolution"/></dd>
					<dt>HeightMap Resolution</dt><dd><input type="range" min="1" max="4096" value="0" field="heightMapResolution"/></dd>
					<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
			<div class="group" name="Brush">
				<dl>
					<dt>Accumulate</dt><dd><input type="checkbox" field="accumulate"/></dd>
					<div class="terrain-brushes"></div>
					<dt>Size</dt><dd><input type="range" min="0" max="100" field="currentBrush.size"/></dd>
					<dt>Strength</dt><dd><input type="range" min="0" max="1" field="currentBrush.strength"/></dd>
					<dt>Step</dt><dd><input type="range" min="0.01" max="10" field="currentBrush.step"/></dd>
					<div class="terrain-surfaces"></div>
				</dl>
			</div>
		');
		var brushes : Array<Dynamic> = ctx.scene.props.get("terrain.brushes");
		var brushesContainer = props.find(".terrain-brushes");
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
				currentBrush.bitmap = new h2d.Bitmap(h2d.Tile.fromTexture(currentBrush.tex));
				currentBrush.bitmap.smooth = true;
				currentBrush.bitmap.color = new h3d.Vector(currentBrush.strength);

				props.remove();
				edit(ctx);
			});
			brushesContainer.append(brushElem);
		}

		var surfacesContainer = props.find(".terrain-surfaces");
		var surfacesPath : Dynamic = ctx.scene.props.get("terrain.surfacesPath");
		var dir = hide.Ide.inst.getPath(surfacesPath);
		for( f in try sys.FileSystem.readDirectory(dir) catch( e : Dynamic ) [] ){
			if( StringTools.endsWith(f,"_Albedo.png") ){
				var label = f.substr(0,f.length -  "_Albedo.png".length);
				var img : Element;
				if( f == currentSurfaceName) img = new Element('<div class="surface-preview-selected"></div>');
				else img = new Element('<div class="surface-preview"></div>');
				var imgPath = dir + f;
				img.css("background-image", 'url("file://$imgPath")');
				var surfaceElem = new Element('<div class=" surface"><span class="tooltiptext">$label</span></div>').prepend(img);
				surfaceElem.click(function(e){
					currentSurfaceName = f;
					props.remove();
					edit(ctx);
				});
				surfacesContainer.append(surfaceElem);
			}
		}

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});

	}
	#end

	static var _ = hxd.prefab.Library.register("Terrain", Terrain);
}