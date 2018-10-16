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

	public var tileSize = 10.0;
	public var cellSize = 1.0;
	public var heightMapResolution : Int = 20;
	public var weightMapResolution : Int = 20;
	public var autoCreateTile = false;
	var tmpSurfacesProps : Array<SurfaceProps> = [];
	public var terrain : h3d.scene.pbr.terrain.Terrain;
	var parallaxAmount = 0.0;
	var parallaxMinStep : Int = 1;
	var parallaxMaxStep : Int = 16;
	var heightBlendStrength : Float = 0.0;
	var heightBlendSharpness : Float = 0.0;
	var packWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.PackWeight());
	var unpackWeight = new h3d.pass.ScreenFx(new hide.prefab.terrain.UnpackWeight());

	#if editor
	var editor : hide.prefab.terrain.TerrainEditor;
	#end

	public function new(?parent) {
		super(parent);
		type = "terrain";
	}

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

	public function saveHeightTextures(ctx : Context){
		for(tile in terrain.tiles){
			var pixels = tile.heightMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "h";
			ctx.shared.savePrefabDat(fileName, "heightMap", name, pixels.bytes);
		}
	}

	public function saveWeightTextures(ctx : Context){
		var packedWeightsTex = new h3d.mat.Texture(terrain.weightMapResolution, terrain.weightMapResolution, [Target], RGBA);
		for(tile in terrain.tiles){
			h3d.Engine.getCurrent().pushTarget(packedWeightsTex);
			packWeight.shader.indexMap = tile.surfaceIndexMap;
			packWeight.shader.weightTextures = tile.surfaceWeightArray;
			packWeight.shader.weightCount = tile.surfaceWeights.length;
			packWeight.render();

			var pixels = packedWeightsTex.capturePixels();
			var bytes = pixels.toPNG();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "w";
			ctx.shared.savePrefabDat(fileName, "png", name, bytes);

			var pixels = tile.surfaceIndexMap.capturePixels();
			var bytes = pixels.toPNG();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "i";
			ctx.shared.savePrefabDat(fileName, "png", name, bytes);
		}
	}

	function loadTerrain(ctx : Context){
		var resDir = ctx.shared.loadDir(name);
		if(resDir == null) return;
		for(res in resDir){
			var file = res.name.split(".")[0];
			var coords = file.split("_");
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			var type = coords[2];
			var tile = terrain.createTile(x, y);
			switch(type){
				case "h":
					var bytes = res.entry.getBytes();
					var pixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(heightMapResolution + 1, heightMapResolution + 1, bytes, RGBA32F);
					tile.heightMap.uploadPixels(pixels);
					tile.refreshMesh();
				case "w":
					var tex = res.toTexture();
					for(i in 0 ... tile.surfaceWeights.length){
						h3d.Engine.getCurrent().pushTarget(tile.surfaceWeights[i]);
						unpackWeight.shader.indexMap = tile.surfaceIndexMap;
						unpackWeight.shader.packedWeightTexture = tex;
						unpackWeight.shader.index = i;
						unpackWeight.render();
					}
					tile.generateWeightArray();
					tex.dispose();
				case"i":
					var tex = res.toTexture();
					tile.surfaceIndexMap = tex.clone();
					tile.surfaceIndexMap.filter = Nearest;
					tile.surfaceIndexMap.flags.set(Target);
					tex.dispose();
			}
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
		terrain.name = "terrain";

		ctx.local3d = terrain;
		ctx.local3d.name = name;

		for(surfaceProps in tmpSurfacesProps){
			var surface = terrain.addEmptySurface();
			var albedo = ctx.shared.loadTexture(surfaceProps.albedo);
			var normal = ctx.shared.loadTexture(surfaceProps.normal);
			var pbr = ctx.shared.loadTexture(surfaceProps.pbr);
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
					//albedo.dispose();
					//normal.dispose();
					//pbr.dispose();
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
				loadTerrain(ctx);
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
		if( editor != null ) editor.setSelected(ctx, b);
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Terrain" };
	}

	override function edit( ctx : EditContext ) {
		//super.edit(ctx); // Only need Pos-Z and Rot-Z
		var props = new hide.Element('<div></div>');
		if( editor == null )editor = new TerrainEditor(this, ctx.properties.undo);
		editor.setupUI(props, ctx);
		props.append('
			<div class="group" name="Terrain"><dl>
				<dt>Pos Z</dt><dd><input type="range" min="-100" max="100" value="0" field="z"/></dd>
				<dt>Rotation Z</dt><dd><input type="range" min="-180" max="180" value="0" field="rotationZ" /></dd>
				<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
				<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				<dt>Mode</dt>
				<dd><select field="editor.renderMode">
					<option value="PBR">PBR</option>
					<option value="ShaderComplexity">Shader Complexity</option>
					<option value="Checker">Checker</option>
				</select></dd>
			</dl></div>
			<div class="group" name="Quality">
				<dt>Tile Size</dt><dd><input type="range" min="1" max="100" value="0" field="tileSizeSet"/></dd>
				<dt>Cell Size</dt><dd><input type="range" min="0.01" max="10" value="0" field="cellSizeSet"/></dd>
				<dt>WeightMap Resolution</dt><dd><input type="range" min="1" max="1000" value="0" step="1" field="weightMapResolutionSet"/></dd>
				<dt>HeightMap Resolution</dt><dd><input type="range" min="1" max="1000" value="0" step="1" field="heightMapResolutionSet"/></dd>
				<div align="center"><input type="button" value="Apply" class="apply"/></div>
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
		');

		props.find(".apply").click(function(_) {
			tileSize = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSet").range.value;
			cellSize = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="cellSizeSet").range.value;
			weightMapResolution = Std.int(@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapResolutionSet").range.value);
			heightMapResolution = Std.int(@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="heightMapResolutionSet").range.value);
			terrain.cellCount = getCellCount();
			terrain.cellSize = getCellSize();
			terrain.tileSize = terrain.cellCount * terrain.cellSize;
			terrain.refreshMesh();
			terrain.heightMapResolution = heightMapResolution;
			terrain.weightMapResolution = weightMapResolution;
			terrain.refreshTex();
			for(tile in terrain.tiles)
				tile.blendEdges();
			if( editor != null )
				editor.refresh();
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
			editor.onChange(ctx, pname, props);
		});

		// Reset values if not applied
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSet").range.value = tileSize;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="cellSizeSet").range.value = cellSize;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapResolutionSet").range.value = weightMapResolution;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="heightMapResolutionSet").range.value = heightMapResolution;
	}
	#end

	static var _ = hxd.prefab.Library.register("terrain", Terrain);
}