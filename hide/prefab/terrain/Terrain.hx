package hide.prefab.terrain;
using Lambda;

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
	public var autoCreateTile = false;
	var tmpSurfacesProps : Array<SurfaceProps> = [];
	public var terrain : h3d.scene.pbr.terrain.Terrain;
	var parallaxAmount = 0.0;
	var parallaxMinStep : Int = 1;
	var parallaxMaxStep : Int = 256;
	var heightBlendStrength : Float = 0.0;
	var heightBlendSharpness : Float = 0.0;
	var packWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.PackWeight());
	var unpackWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.UnpackWeight());

	#if editor
	var editor : hide.prefab.terrain.TerrainEditor;
	#end

	override function load( obj : Dynamic ) {
		super.load(obj);
		tileSize = obj.tileSize == null ? 1 : obj.tileSize;
		cellSize = obj.cellSize == null ? 1 : obj.cellSize;
		heightMapResolution = obj.heightMapResolution == null ? 1 : hxd.Math.ceil(obj.heightMapResolution);
		weightMapResolution = obj.weightMapResolution == null ? 1 : hxd.Math.ceil(obj.weightMapResolution);
		if( obj.surfaces != null ) tmpSurfacesProps = obj.surfaces;
		parallaxAmount = obj.parallaxAmount == null ? 0.0 : obj.parallaxAmount;
		parallaxMinStep = obj.parallaxMinStep == null ? 1 : obj.parallaxMinStep;
		parallaxMaxStep = obj.parallaxMaxStep == null ? 1 : obj.parallaxMaxStep;
		heightBlendStrength = obj.heightBlendStrength == null ? 0 : obj.heightBlendStrength;
		heightBlendSharpness = obj.heightBlendSharpness == null ? 0 : obj.heightBlendSharpness;
		autoCreateTile = obj.autoCreateTile == null ? false : obj.autoCreateTile;
	}

	override function save() {
		var obj : Dynamic = super.save();
		if( tileSize > 0 ) obj.tileSize = tileSize;
		if( cellSize > 0 ) obj.cellSize = cellSize;
		if( heightMapResolution > 0 ) obj.heightMapResolution = hxd.Math.ceil(heightMapResolution);
		if( weightMapResolution > 0 ) obj.weightMapResolution = hxd.Math.ceil(weightMapResolution);
		obj.parallaxAmount = parallaxAmount;
		obj.parallaxMinStep = parallaxMinStep;
		obj.parallaxMaxStep = parallaxMaxStep;
		obj.heightBlendStrength = heightBlendStrength;
		obj.heightBlendSharpness = heightBlendSharpness;
		obj.autoCreateTile = autoCreateTile;
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

		var packedWeightsTex = new h3d.mat.Texture(terrain.weightMapResolution, terrain.weightMapResolution, [Target], RGBA);
		for(tile in terrain.tiles){
			h3d.Engine.getCurrent().pushTarget(packedWeightsTex);
			packWeight.shader.indexMap = tile.surfaceIndexMap;
			packWeight.shader.weightTextures = tile.surfaceWeightArray;
			packWeight.shader.weightCount = tile.surfaceWeights.length;
			packWeight.render();

			var pixels = packedWeightsTex.capturePixels();
			var bytes = pixels.toPNG();
			var name = tile.tileX + "_" + tile.tileY + "_" + "w";
			ctx.shared.saveTexture(name, bytes, dir, "png");

			var pixels = tile.surfaceIndexMap.capturePixels();
			var bytes = pixels.toPNG();
			var name = tile.tileX + "_" + tile.tileY + "_" + "i";
			ctx.shared.saveTexture(name, bytes, dir, "png");
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
			var pixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(heightMapResolution + 1, heightMapResolution + 1, bytes, RGBA32F);
			var tile = terrain.createTile(x, y);
			tile.heightMap.uploadPixels(pixels);
			tile.refreshMesh();
		}
	}

	function loadWeightTextures(ctx : Context){
		var dir = ctx.shared.currentPath.split(".l3d")[0] + "_terrain";
		var files = sys.FileSystem.readDirectory(hide.Ide.inst.getPath(dir));

		for(file in files){
			var texName = file.split(".png")[0];
			var coords = texName.split("_");
			if(coords[2] != "i") continue;
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			var tile = terrain.createTile(x, y);
			var tex = ctx.loadTexture(dir + "/" + file);

			function wait() {
				if( tex.flags.has(Loading) ) haxe.Timer.delay(wait, 1);
				else {
					tile.surfaceIndexMap = tex.clone();
					tile.surfaceIndexMap.filter = Nearest;
					tile.surfaceIndexMap.flags.set(Target);
					tex.dispose();
				}
			}
			wait();
		}

		for(file in files){
			var texName = file.split(".png")[0];
			var coords = texName.split("_");
			if(coords[2] != "w") continue;
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			var tile = terrain.createTile(x, y);
			var tex = ctx.loadTexture(dir + "/" + file);

			function wait() {
				if( tex.flags.has(Loading) || tile.surfaceIndexMap == null) haxe.Timer.delay(wait, 1);
				else {
					for(i in 0 ... tile.surfaceWeights.length){
						h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
						unpackWeight.shader.indexMap = tile.surfaceIndexMap;
						unpackWeight.shader.packedWeightTexture = tex;
						unpackWeight.shader.index = i;
						unpackWeight.render();
					}
					tile.generateWeightArray();
					tex.dispose();
				}
			}
			wait();
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		terrain = new h3d.scene.pbr.terrain.Terrain(ctx.local3d);
		terrain.cellCount = getCellCount();
		terrain.cellSize = getCellSize();
		terrain.tileSize = terrain.cellCount * terrain.cellSize;
		terrain.refreshMesh();
		terrain.heightMapResolution = heightMapResolution;
		terrain.weightMapResolution = weightMapResolution;
		terrain.parallaxAmount = parallaxAmount / 10;
		terrain.parallaxMinStep = parallaxMinStep;
		terrain.parallaxMaxStep = parallaxMaxStep;
		terrain.heightBlendStrength = heightBlendStrength;
		terrain.heightBlendSharpness = heightBlendSharpness;

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
				for(tile in terrain.tiles)
					tile.blendEdges();
			}
			else
				haxe.Timer.delay(waitAll, 1);
		}
		waitAll();

		updateInstance(ctx);

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);

		#if editor
		if(propName == "editor.currentSurface.tilling"
		|| propName == "editor.currentSurface.offset.x"
		|| propName == "editor.currentSurface.offset.y"
		|| propName == "editor.currentSurface.angle"
		|| propName == "editor.currentSurface.parallaxAmount")
			terrain.updateSurfaceParams();

		if(propName == "tileSize" || propName == "cellSize"){
			terrain.cellCount = getCellCount();
			terrain.cellSize = getCellSize();
			terrain.tileSize = terrain.cellCount * terrain.cellSize;
			terrain.refreshMesh();
		}

		if(propName == "heightMapResolution" || propName == "weightMapResolution"){
			terrain.heightMapResolution = heightMapResolution;
			terrain.weightMapResolution = weightMapResolution;
			terrain.refreshTex();
		}

		if(propName == "terrain.correctUV"){
			terrain.refreshMesh();
		}

		terrain.parallaxAmount = parallaxAmount / 10.0;
		terrain.parallaxMinStep = parallaxMinStep;
		terrain.parallaxMaxStep = parallaxMaxStep;
		terrain.heightBlendStrength = heightBlendStrength;
		terrain.heightBlendSharpness = heightBlendSharpness;

		if(editor != null) editor.update(propName);
		#end
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

	#if editor
	override function setSelected( ctx : Context, b : Bool ) {
		editor.setSelected(ctx, b);
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "terrain" };
	}

	override function edit( ctx : EditContext ) {

		//super.edit(ctx);
		if( editor == null ) editor = new TerrainEditor(this, ctx.properties.undo);

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
					<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
			<div class="group" name="Blend">
				<dt>HeightBlend</dt><dd><input type="range" min="0" max="1" field="heightBlendStrength"/></dd>
				<dt>Sharpness</dt><dd><input type="range" min="0" max="1" field="heightBlendSharpness"/></dd>
			</div>
			<div class="group" name="Parallax">
				<dt>Amount</dt><dd><input type="range" min="0" max="1" field="parallaxAmount"/></dd>
				<dt>Min Step</dt><dd><input type="range" min="1" max="256" value="0" step="1" field="parallaxMinStep"/></dd>
				<dt>Max Step</dt><dd><input type="range" min="1" max="256" value="0" step="1" field="parallaxMaxStep"/></dd>
			</div>
			<div class="group" name="Mode">
				<dt>Accumulate</dt><dd><input type="checkbox" field="editor.currentBrush.brushMode.accumulate"/></dd>
				<dt>Mode</dt>
				<dd><select field="editor.currentBrush.brushMode.mode">
					<option value="Paint">Paint</option>
					<option value="Sculpt">Sculpt</option>
					<option value="Delete">Delete</option>
				</select></dd>
				<dt>AutoCreate</dt><dd><input type="checkbox" field="autoCreateTile"/></dd>
			</div>
			<div class="group" name="Brush">
				<dl>
					<div class="terrain-brushes"></div>
					<dt>Size</dt><dd><input type="range" min="0.01" max="10" field="editor.currentBrush.size"/></dd>
					<dt>Strength</dt><dd><input type="range" min="0" max="1" field="editor.currentBrush.strength"/></dd>
					<dt>Step</dt><dd><input type="range" min="0.01" max="10" field="editor.currentBrush.step"/></dd>
				</dl>
			</div>
			<div class="group" name="Surface">
				<dt>Add</dt><dd><input type="texturepath" field="editor.tmpTexPath"/></dd>
				<div class="terrain-surfaces"></div>
				<dt>Tilling</dt><dd><input type="range" min="0" max="10" field="editor.currentSurface.tilling"/></dd>
				<dt>Offset X</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.x"/></dd>
				<dt>Offset Y</dt><dd><input type="range" min="0" max="1" field="editor.currentSurface.offset.y"/></dd>
				<dt>Rotate</dt><dd><input type="range" min="0" max="360" field="editor.currentSurface.angle"/></dd>
			</div>
			<div><dl><input type="button" value="Save" class="save"/><dl></div>
		');

		props.find(".save").click(function(_) {
			var dir = ctx.rootContext.shared.currentPath.split(".l3d")[0] + "_terrain";
			var dirPath = hide.Ide.inst.getPath(dir);
			var files = sys.FileSystem.readDirectory(dirPath);
			for(file in files){
				var name = file.split(".heightMap")[0];
				name = name.split(".png")[0];
				var coords = name.split("_");
				if(coords[2] != "h" && coords[2] != "i" && coords[2] != "w") continue;
				sys.FileSystem.deleteFile(dirPath + "/" + file);
			}
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
				if( brush.name == editor.currentBrush.name) img = new Element('<div class="brush-preview-selected"></div>');
				else img = new Element('<div class="brush-preview"></div>');
				img.css("background-image", 'url("file://${hide.Ide.inst.getPath(brush.texture)}")');
				var brushElem = new Element('<div class="brush"><span class="tooltiptext">$label</span></div>').prepend(img);
				brushElem.click(function(e){
					editor.currentBrush.size = brush.size;
					editor.currentBrush.strength = brush.strength;
					editor.currentBrush.step = brush.step;
					editor.currentBrush.texPath = hide.Ide.inst.getPath(brush.texture);
					editor.currentBrush.tex = loadTexture(ctx, editor.currentBrush.texPath);
					editor.currentBrush.name = brush.name;
					if(editor.currentBrush.bitmap != null){
						editor.currentBrush.bitmap.tile.dispose();
						editor.currentBrush.bitmap.tile = h2d.Tile.fromTexture(editor.currentBrush.tex);
					}
					else
						editor.currentBrush.bitmap = new h2d.Bitmap(h2d.Tile.fromTexture(editor.currentBrush.tex));
					editor.currentBrush.bitmap.smooth = true;
					editor.currentBrush.bitmap.color = new h3d.Vector(editor.currentBrush.strength);
					refreshBrushes();
				});
				brushesContainer.append(brushElem);
			}
			if(editor.currentBrush != null){
				setRange("editor.currentBrush.size", editor.currentBrush.size);
				setRange("editor.currentBrush.strength", editor.currentBrush.strength);
				setRange("editor.currentBrush.step", editor.currentBrush.step);
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
				if( i == editor.currentBrush.index) img = new Element('<div class="surface-preview-selected"></div>');
				else img = new Element('<div class="surface-preview"></div>');
				var imgPath = hide.Ide.inst.getPath(surface.albedo.name);
				img.css("background-image", 'url("file://$imgPath")');
				var surfaceElem = new Element('<div class=" surface"><span class="tooltiptext">$label</span></div>').prepend(img);
				surfaceElem.click(function(e){
					editor.currentBrush.index = i;
					editor.currentSurface = terrain.getSurface(i);
					refreshSurfaces();
				});
				surfacesContainer.append(surfaceElem);
			}
			if(editor.currentSurface != null){
				setRange("editor.currentSurface.tilling", editor.currentSurface.tilling);
				setRange("editor.currentSurface.offset.x", editor.currentSurface.offset.x);
				setRange("editor.currentSurface.offset.y", editor.currentSurface.offset.y);
				setRange("editor.currentSurface.angle", editor.currentSurface.angle);
			}
		};
		refreshSurfaces();

		ctx.properties.add(props, this, function(pname) {
			if(pname == "editor.tmpTexPath"){
				var split : Array<String> = [];
				var curTypeIndex = 0;
				while( split.length <= 1 && curTypeIndex < editor.textureType.length){
					split = editor.tmpTexPath.split(editor.textureType[curTypeIndex]);
					curTypeIndex++;
				}
				if(split.length > 1) {
					var t : h3d.mat.Texture;
					var name = split[0];
					var albedo = ctx.rootContext.shared.loadTexture(name + editor.textureType[0] + ".png");
					var normal = ctx.rootContext.shared.loadTexture(name + editor.textureType[1] + ".png");
					var pbr = ctx.rootContext.shared.loadTexture(name + editor.textureType[2] + ".png");
					function wait() {
						if( albedo.flags.has(Loading) || normal.flags.has(Loading)|| pbr.flags.has(Loading))
							haxe.Timer.delay(wait, 1);
						else{
							if(terrain.getSurfaceFromTex(name + editor.textureType[0] + ".png", name + editor.textureType[1] + ".png", name + editor.textureType[2] + ".png") == null){
								terrain.addSurface(albedo, normal, pbr);
								terrain.generateSurfaceArray();
								props.remove();
								edit(ctx);
							}
							albedo.dispose();
							normal.dispose();
							pbr.dispose();
						}
					}
					wait();
				}
			}
			editor.tmpTexPath = null;

		ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = hxd.prefab.Library.register("Terrain", Terrain);
}