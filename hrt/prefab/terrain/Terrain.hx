package hrt.prefab.terrain;
using Lambda;

typedef SurfaceProps = {
	albedo : String,
	normal : String,
	pbr : String,
	tilling : Float,
	angle : Float,
	offsetX : Float,
	offsetY : Float,
	minHeight : Float,
	maxHeight : Float,
};

@:access(hrt.prefab.terrain.TerrainMesh)
class Terrain extends Object3D {

	public var terrain : TerrainMesh;

	// Tile Param
	public var tileSize = 64.0; // Size of the tile
	public var cellSize = 1.0; // Size of a quad of the Tile, cellCount = tileSize / cellSize
	// Texture Param
	public var heightMapResolution : Int = 64;
	public var weightMapResolution : Int = 128;
	// Parallax Param
	var parallaxAmount = 0.0;
	var parallaxMinStep : Int = 1;
	var parallaxMaxStep : Int = 16;
	// Blend Param
	var heightBlendStrength : Float = 0.0;
	var blendSharpness : Float = 0.0;
	// Shadows Param
	var castShadows = false;
	// Data for binary save/load
	var surfaceCount = 0;
	var surfaceSize = 0;
	// Utility
	var tmpSurfacesProps : Array<SurfaceProps> = [];
	var unpackWeight = new h3d.pass.ScreenFx(new UnpackWeight());
	var modified = false;

	#if editor
	var packWeight = new h3d.pass.ScreenFx(new PackWeight());
	var editor : hide.prefab.terrain.TerrainEditor;
	var cachedInstance : TerrainMesh;
	public var showChecker = false;
	public var autoCreateTile = false;
	#end

	public function new( ?parent ) {
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
		blendSharpness = obj.blendSharpness == null ? 0 : obj.blendSharpness;
		surfaceCount = obj.surfaceCount == null ? 0 : obj.surfaceCount;
		surfaceSize = obj.surfaceSize == null ? 0 : obj.surfaceSize;
		castShadows = obj.castShadows == null ? false : obj.castShadows;
		#if editor
		autoCreateTile = obj.autoCreateTile == null ? false : obj.autoCreateTile;
		showChecker = obj.showChecker == null ? false : obj.showChecker;
		#end
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
		obj.blendSharpness = blendSharpness;
		obj.castShadows = castShadows;
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
				offsetY : surface.offset.y,
				minHeight : surface.minHeight,
				maxHeight : surface.maxHeight,
			};
			surfacesProps.push(surfaceProps);
		}
		obj.surfaces = surfacesProps;
		obj.surfaceCount = terrain.surfaces.length == 0 ? 0 : terrain.surfaceArray.surfaceCount;
		obj.surfaceSize = terrain.surfaces.length == 0 ? 0 : terrain.surfaceArray.albedo.width;

		#if editor
		obj.autoCreateTile = autoCreateTile;
	 	obj.showChecker = terrain.showChecker;
		if( modified ) {
			modified = false;
			if( editor != null && terrain.surfaces.length > 0 ) editor.saveTextures();
		}
		#end

		return obj;
	}

	function loadTiles( ctx : Context, height = true, index = true , weight = true ) {
		var prevWatch = @:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH;
		@:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH = false;
		var resDir = ctx.shared.loadDir(name);

		if( resDir == null )
			return;

		// Avoid texture alloc for unpacking
		var tmpPackedWeightTexture = new h3d.mat.Texture(terrain.weightMapResolution, terrain.weightMapResolution, [Target]);

		for( res in resDir ) {
			var fileInfos = res.name.split(".");
			var ext = fileInfos[1];
			var file = fileInfos[0];
			var coords = file.split("_");
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			if( x == null || y == null ) continue;
			var type = coords[2];
			var tile = terrain.createTile(x, y, false);
			tile.material.shadows = castShadows;

			#if editor
			tile.material.mainPass.stencil = new h3d.mat.Stencil();
			tile.material.mainPass.stencil.setFunc(Always, 0x01, 0x01, 0x01);
			tile.material.mainPass.stencil.setOp(Keep, Keep, Replace);
			#end

			switch( type ) {
				case "n":
				#if !editor
				var bytes = res.entry.getBytes();
				tile.createBigPrim(bytes);
				#end
				case "h":
				if( height ) {
					var bytes = res.entry.getBytes();
					var pixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(heightMapResolution + 1, heightMapResolution + 1, bytes, RGBA32F);
					@:privateAccess tile.heightmapPixels = pixels;
					#if editor
					if( tile.heightMap == null ) @:privateAccess tile.refreshHeightMap();
					tile.heightMap.uploadPixels(pixels);
					tile.refreshGrid();
					#end
				}
				case "w":
				if( weight ) {
					if( ext == "png" ) { // Retro-compatibility
						var weightAsPNG = res.toTexture();
						h3d.pass.Copy.run(weightAsPNG, tmpPackedWeightTexture);
						tile.packedWeightMapPixel = tmpPackedWeightTexture.capturePixels();
						weightAsPNG.dispose();
					} else {
						var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution, terrain.weightMapResolution, res.entry.getBytes(), RGBA);
						tmpPackedWeightTexture.uploadPixels(pixels);
						tile.packedWeightMapPixel = pixels;
					}

					// Notice that we need the surfaceIndexMap loaded before doing the unpacking
					var engine = h3d.Engine.getCurrent();
					#if editor
					// Unpack weight from RGBA texture into a array of texture of R8, and create the TextureArray
					if( tile.surfaceWeights.length == 0 )
						@:privateAccess tile.refreshSurfaceWeightArray();
					for( i in 0 ... tile.surfaceWeights.length ) {
						engine.pushTarget(tile.surfaceWeights[i]);
						unpackWeight.shader.indexMap = tile.surfaceIndexMap;
						unpackWeight.shader.packedWeightTexture = tmpPackedWeightTexture;
						unpackWeight.shader.index = i;
						unpackWeight.render();
						engine.popTarget();
					}
					tile.generateWeightTextureArray();
					#else
					// Unpack weight from RGBA texture directly into the TextureArray of R8
					tile.generateWeightTextureArray();
					for( i in 0 ... terrain.surfaceArray.surfaceCount ) {
						engine.pushTarget(tile.surfaceWeightArray, i);
						unpackWeight.shader.indexMap = tile.surfaceIndexMap;
						unpackWeight.shader.packedWeightTexture = tmpPackedWeightTexture;
						unpackWeight.shader.index = i;
						unpackWeight.render();
						engine.popTarget();
					}
					#end
				}
				case"i":
				if( index ) {
					if( tile.surfaceIndexMap == null ) @:privateAccess tile.refreshIndexMap();
					if( ext == "png" ) { // Retro-compatibility
						var indexAsPNG = res.toTexture();
						h3d.pass.Copy.run(indexAsPNG, tile.surfaceIndexMap);
						tile.indexMapPixels = tile.surfaceIndexMap.capturePixels();
						indexAsPNG.dispose();
					}
					else {
						var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution, terrain.weightMapResolution, res.entry.getBytes(), RGBA);
						tile.indexMapPixels = pixels;
						tile.surfaceIndexMap.uploadPixels(pixels);
					}
				}
			}
			tmpPackedWeightTexture.dispose();
		}

		#if editor
		for( t in terrain.tiles ) {
			if( t == null ) {
				"Missing tile" + terrain.tiles.indexOf(t);
				continue;
			}
			if( t.heightMap == null ) trace("Missing heightmap for tile" + terrain.tiles.indexOf(t));
			if( t.surfaceIndexMap == null ) trace("Missing surfaceIndexMap for tile" + terrain.tiles.indexOf(t));
			if( t.surfaceWeightArray == null ) trace("Missing surfaceWeightArray for tile" + terrain.tiles.indexOf(t));
		}
		#end

		@:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH = prevWatch;
	}

	function loadSurfaces( ctx : Context, onEnd : Void -> Void ) {
		for( surfaceProps in tmpSurfacesProps ) {
			var surface = terrain.addEmptySurface();
		}
		for( i in 0 ... tmpSurfacesProps.length ) {
			var surfaceProps = tmpSurfacesProps[i];
			var surface = terrain.getSurface(i);
			var albedo = ctx.shared.loadTexture(surfaceProps.albedo);
			var normal = ctx.shared.loadTexture(surfaceProps.normal);
			var pbr = ctx.shared.loadTexture(surfaceProps.pbr);
			function wait() {
				if( albedo.isDisposed() || albedo.flags.has(Loading) || normal.flags.has(Loading) || pbr.flags.has(Loading) )
					return;

				albedo.preventAutoDispose();
				normal.preventAutoDispose();
				pbr.preventAutoDispose();
				surface.albedo = albedo;
				surface.normal = normal;
				surface.pbr = pbr;
				surface.offset.x = surfaceProps.offsetX;
				surface.offset.y = surfaceProps.offsetY;
				surface.angle = surfaceProps.angle;
				surface.tilling = surfaceProps.tilling;
				surface.minHeight = surfaceProps.minHeight;
				onEnd();
			}
			albedo.waitLoad(wait);
			normal.waitLoad(wait);
			pbr.waitLoad(wait);
		}
	}

	public function initTerrain( ctx : Context, height = true, surface = true ) {
		//#if editor
		if( surface ) {
			var initDone = false;
			function waitAll() {

				if( initDone )
					return;

				for( surface in terrain.surfaces ) {
					if( surface == null || surface.albedo == null || surface.normal == null || surface.pbr == null )
						return;
				}
				terrain.generateSurfaceArray();

				loadTiles(ctx, height, surface, surface);

				#if editor
				for( t in terrain.tiles )
					t.computeEdgesNormals();
				#end

				initDone = true;
			}
			loadSurfaces(ctx, waitAll);
		}
		else {
			loadTiles(ctx, height, surface, surface);
			for( t in terrain.tiles )
				t.computeEdgesNormals();
		}
		//#else
		//loadBinary(ctx);
		//#end
	}


	#if editor

	public function saveHeightTextures( ctx : Context ) {
		for( tile in terrain.tiles ) {
			var pixels = tile.heightMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "h";
			ctx.shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	public function saveNormals( ctx : Context ) {
		for( tile in terrain.tiles ) {
			if( tile.grid == null || tile.grid.normals == null ) continue;
			var normals = tile.grid.normals;
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "n";
			var bytes = haxe.io.Bytes.alloc(normals.length * 3 * 4);
			for( i in 0 ... normals.length ) {
				bytes.setFloat(i*3*4, normals[i].x);
				bytes.setFloat(i*3*4+4, normals[i].y);
				bytes.setFloat(i*3*4+8, normals[i].z);
			}
			ctx.shared.savePrefabDat(fileName, "bin", name, bytes);
		}
	}

	public function saveWeightTextures( ctx : Context ) {
		var packedWeightsTex = new h3d.mat.Texture(terrain.weightMapResolution, terrain.weightMapResolution, [Target], RGBA);
		for( tile in terrain.tiles ) {
			h3d.Engine.getCurrent().pushTarget(packedWeightsTex);
			packWeight.shader.indexMap = tile.surfaceIndexMap;
			packWeight.shader.weightTextures = tile.surfaceWeightArray;
			packWeight.shader.weightCount = tile.surfaceWeights.length;
			packWeight.render();

			var pixels = packedWeightsTex.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "w";
			ctx.shared.savePrefabDat(fileName, "bin", name, pixels.bytes);

			var pixels = tile.surfaceIndexMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "i";
			ctx.shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	public function saveSurfaceArray( ctx : Context ) {
		var count = terrain.surfaces.length;
		for( i in 0 ... count ) {
			var pixels = terrain.surfaceArray.albedo.capturePixels(i);
			ctx.shared.savePrefabDat("albedo_" + i, "bin", name, pixels.bytes);
			var pixels = terrain.surfaceArray.pbr.capturePixels(i);
			ctx.shared.savePrefabDat("pbr_" + i, "bin", name, pixels.bytes);
			var pixels = terrain.surfaceArray.normal.capturePixels(i);
			ctx.shared.savePrefabDat("normal_" + i, "bin", name, pixels.bytes);
		}
	}

	#end

	public function loadBinary( ctx : Context ) {

		terrain.surfaceArray = new Surface.SurfaceArray(surfaceCount, surfaceSize);

		var resDir = ctx.shared.loadDir(name);
		if( resDir == null ) return;

		/*for( res in resDir ) {
			var fileInfos = res.name.split(".");
			var ext = fileInfos[1];
			var file = fileInfos[0];
			if( ext != "bin" ) continue;
			var texInfos = file.split("_");
			var texType = texInfos[0];
			var face = Std.parseInt(texInfos[1]);
			var bytes = res.entry.getBytes();
			var pixels = new hxd.Pixels(surfaceSize, surfaceSize, bytes, RGBA);
			switch( texType ) {
				case "albedo" : terrain.surfaceArray.albedo.uploadPixels(pixels, 0, face);
				case "pbr" : terrain.surfaceArray.pbr.uploadPixels(pixels, 0, face);
				case "normal" : terrain.surfaceArray.normal.uploadPixels(pixels, 0, face);
			}
		}*/

		var pixels = hxd.Pixels.alloc(surfaceSize, surfaceSize, RGBA);
		for(i in 0 ... pixels.width)
			for(j in 0 ... pixels.height)
				pixels.setPixel(i,j, 0xFF0000);
		terrain.surfaceArray.albedo.uploadPixels(pixels, 0, 0);
		for(i in 0 ... pixels.width)
			for(j in 0 ... pixels.height)
				pixels.setPixel(i,j, 0x00FF00);
		terrain.surfaceArray.albedo.uploadPixels(pixels, 0, 1);
		for(i in 0 ... pixels.width)
			for(j in 0 ... pixels.height)
				pixels.setPixel(i,j, 0x0000FF);
		terrain.surfaceArray.albedo.uploadPixels(pixels, 0, 2);

		var pixels = hxd.Pixels.alloc(surfaceSize, surfaceSize, RGBA);
		terrain.surfaceArray.normal.uploadPixels(pixels, 0, 0);
		terrain.surfaceArray.normal.uploadPixels(pixels, 0, 1);
		terrain.surfaceArray.normal.uploadPixels(pixels, 0, 2);

		var pixels = hxd.Pixels.alloc(surfaceSize, surfaceSize, RGBA);
		terrain.surfaceArray.pbr.uploadPixels(pixels, 0, 0);
		terrain.surfaceArray.pbr.uploadPixels(pixels, 0, 1);
		terrain.surfaceArray.pbr.uploadPixels(pixels, 0, 2);

		terrain.updateSurfaceParams();
		terrain.refreshAllTex();
		loadTiles(ctx, true, true, true);
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);


		#if editor
		// Attach the terrain to the scene directly, avoid slow refresh
		if( cachedInstance != null ) {
			ctx.local3d = terrain;
			ctx.local3d.name = name;
			updateInstance(ctx);
			return ctx;
		}
		else {
			terrain = new TerrainMesh(ctx.local3d.getScene());
			cachedInstance = terrain;
		}
		#else
		terrain = new TerrainMesh(ctx.local3d);
		#end

		terrain.cellCount = getCellCount();
		terrain.cellSize = getCellSize();
		terrain.tileSize = terrain.cellCount * terrain.cellSize;
		terrain.heightMapResolution = heightMapResolution;
		terrain.weightMapResolution = weightMapResolution;
		terrain.parallaxAmount = parallaxAmount / 10;
		terrain.parallaxMinStep = parallaxMinStep;
		terrain.parallaxMaxStep = parallaxMaxStep;
		terrain.heightBlendStrength = heightBlendStrength;
		terrain.blendSharpness = blendSharpness;
		terrain.name = "terrain";

		ctx.local3d = terrain;
		ctx.local3d.name = name;

		#if editor
		// Auto init in editor
		initTerrain(ctx, true, true);
		#end

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
		terrain.blendSharpness = blendSharpness;
		terrain.showChecker = showChecker;

		if( propName == "castShadows" ) {
			if( terrain != null ) {
				for( t in terrain.tiles )
					t.material.castShadows = castShadows;
			}
		}

		if( editor != null )
			editor.update(propName);
		#end
	}

	function getCellCount() {
		var resolution = Math.max(0.1, cellSize);
		var cellCount = Math.ceil(Math.min(1000, tileSize / resolution));
		return cellCount;
	}

	function getCellSize() {
		var cellCount = getCellCount();
		var finalCellSize = tileSize / cellCount;
		return finalCellSize;
	}

	#if editor
	override function makeInteractive( ctx : Context ) : h3d.scene.Interactive {
		return null;
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if( editor != null ) editor.setSelected(ctx, b);
	}

	override function getHideProps() : HideProps {
		return { icon : "industry", name : "Terrain" };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = new hide.Element('<div></div>');
		if( editor == null ) editor = new hide.prefab.terrain.TerrainEditor(this, ctx.properties.undo);
		editor.editContext = ctx;
		editor.setupUI(props, ctx);
		props.append('
			<div class="group" name="Rendering"><dl>
				<dt>Cast Shadows</dt><dd><input type="checkbox" field="castShadows"/></dd>
				<dt>Height Blend</dt><dd><input type="range" min="0" max="1" field="heightBlendStrength"/></dd>
				<dt>Sharpness</dt><dd><input type="range" min="0" max="1" field="blendSharpness"/></dd>
			</dl></div>
			<div class="group" name="Parallax"><dl>
				<dt>Amount</dt><dd><input type="range" min="0" max="1" field="parallaxAmount"/></dd>
				<dt>Min Step</dt><dd><input type="range" min="1" max="64" value="0" step="1" field="parallaxMinStep"/></dd>
				<dt>Max Step</dt><dd><input type="range" min="1" max="64" value="0" step="1" field="parallaxMaxStep"/></dd>
			</dl></div>
			<div class="group" name="Quality"><dl>
				<dt>Tile Size</dt><dd><input type="range" min="1" max="100" value="0" field="tileSizeSet"/></dd>
				<dt>Cell Size</dt><dd><input type="range" min="0.01" max="10" value="0" field="cellSizeSet"/></dd>
				<dt>WeightMap Resolution</dt><dd><input type="range" min="1" max="256" value="0" step="1" field="weightMapResolutionSet"/></dd>
				<dt>HeightMap Resolution</dt><dd><input type="range" min="1" max="256" value="0" step="1" field="heightMapResolutionSet"/></dd>
				<div align="center"><input type="button" value="Apply" class="apply"/></div>
			</dl></div>
			<div class="group" name="Debug"><dl>
				<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
				<dt>Mode</dt>
				<dd><select field="editor.renderMode">
						<option value="PBR">PBR</option>
						<option value="ShaderComplexity">Shader Complexity</option>
						<option value="Checker">Checker</option>
					</select></dd>
			</dl></div>
		');

		props.find(".apply").click(function(_) {
			tileSize = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSet").range.value;
			cellSize = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="cellSizeSet").range.value;
			weightMapResolution = Std.int(@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapResolutionSet").range.value);
			heightMapResolution = Std.int(@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="heightMapResolutionSet").range.value);
			terrain.cellCount = getCellCount();
			terrain.cellSize = getCellSize();
			terrain.tileSize = terrain.cellCount * terrain.cellSize;
			terrain.refreshAllGrids();
			terrain.heightMapResolution = heightMapResolution;
			terrain.weightMapResolution = weightMapResolution;
			terrain.refreshAllTex();
			for( tile in terrain.tiles )
				tile.blendEdges();
			if( editor != null )
				editor.refresh();
			modified = true;
		});

		ctx.properties.add(props, this, function(pname) {
			modified = true;
			ctx.onChange(this, pname);
		});

		// Reset values if not applied
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSet").range.value = tileSize;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="cellSizeSet").range.value = cellSize;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapResolutionSet").range.value = weightMapResolution;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="heightMapResolutionSet").range.value = heightMapResolution;
	}
	#end

	static var _ = Library.register("terrain", Terrain);
}