package hrt.prefab.terrain;
import hxd.Pixels.PixelsFloat;
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
	public var tileSizeX : Float = 64.0;
	public var tileSizeY : Float = 64.0;
	public var vertexPerMeter : Float = 1.0;
	// Texture Param
	public var weightMapPixelPerMeter : Float = 1.0;
	// Parallax Param
	public var parallaxAmount = 0.0;
	public var parallaxMinStep : Int = 1;
	public var parallaxMaxStep : Int = 16;
	// Blend Param
	public var heightBlendStrength : Float = 0.0;
	public var blendSharpness : Float = 0.0;
	// Shadows Param
	public var castShadows = false;
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
	public var brushOpacity : Float;
	var myContext : Context;
	#end

	// Backward Compatibility
	var oldHeightMapResolution : Int = -1;
	var oldWeightMapResolution : Int = -1;
	var oldCellSize : Float = -1;
	var needFormatUpdate = false;

	public function new( ?parent ) {
		super(parent);
		type = "terrain";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		// Backward Compatibility
		if( obj.cellSize != null ) oldCellSize = obj.cellSize;
		if( obj.heightMapResolution != null ) oldHeightMapResolution = hxd.Math.ceil(obj.heightMapResolution);
		if( obj.weightMapResolution != null ) oldWeightMapResolution = hxd.Math.ceil(obj.weightMapResolution);
		if( obj.tileSize != null ) {
			tileSizeX = obj.tileSize;
			tileSizeY = obj.tileSize;
		}
		else {
			tileSizeX = obj.tileSizeX == null ? 1 : obj.tileSizeX;
			tileSizeY = obj.tileSizeY == null ? 1 : obj.tileSizeY;
		}
		if( obj.vertexPerMeter != null ) vertexPerMeter = obj.vertexPerMeter;
		if( obj.weightMapPixelPerMeter != null ) weightMapPixelPerMeter = obj.weightMapPixelPerMeter;
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
		brushOpacity = obj.brushOpacity == null ? 1.0 : obj.brushOpacity;
		#end
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.tileSizeX = tileSizeX;
		obj.tileSizeY = tileSizeY;
		obj.vertexPerMeter = vertexPerMeter;
		obj.weightMapPixelPerMeter = weightMapPixelPerMeter;
		obj.parallaxAmount = parallaxAmount;
		obj.parallaxMinStep = parallaxMinStep;
		obj.parallaxMaxStep = parallaxMaxStep;
		obj.heightBlendStrength = heightBlendStrength;
		obj.blendSharpness = blendSharpness;
		obj.castShadows = castShadows;
		if( terrain != null && terrain.surfaces != null ) {

			obj.surfaceCount = terrain.surfaces.length == 0 ? 0 : terrain.surfaceArray.surfaceCount;
			obj.surfaceSize = terrain.surfaces.length == 0 ? 0 : terrain.surfaceArray.albedo.width;

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
		}
		else {
			// When cloning
			obj.surfaces = tmpSurfacesProps;
			obj.surfaceCount = tmpSurfacesProps.length;
		}

		#if editor
		obj.brushOpacity = brushOpacity;
		obj.autoCreateTile = autoCreateTile;
		if( terrain != null ) obj.showChecker = terrain.showChecker;
		if( modified ) {
			modified = false;
			saveTextures(myContext);
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
		var tmpPackedWeightTexture = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target]);

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
					var pixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(terrain.heightMapResolution.x + 1, terrain.heightMapResolution.y + 1, bytes, RGBA32F);
					@:privateAccess tile.heightmapPixels = pixels;
					#if editor
					// Need heightmap texture for editing
					@:privateAccess tile.refreshHeightMap();
					tile.heightMap.uploadPixels(pixels);
					tile.needNewPixelCapture = false;
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
						var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution.x, terrain.weightMapResolution.y, res.entry.getBytes(), RGBA);
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
						var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution.x, terrain.weightMapResolution.y, res.entry.getBytes(), RGBA);
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

		// Fix terrain being reloaded after a scene modification
		if( terrain.surfaceArray != null )
			return;

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

		// Backward Compatibility
		if( needFormatUpdate ) {
			for( s in terrain.surfaces )
				s.tilling /= tileSizeX;
			terrain.updateSurfaceParams();
			#if editor
			// Need to create a terrain with the new params before saving
			terrain.weightMapResolution = new h2d.col.IPoint(Math.round(tileSizeX * weightMapPixelPerMeter), Math.round(tileSizeY * weightMapPixelPerMeter));
			terrain.cellCount = new h2d.col.IPoint(Math.ceil(tileSizeX * vertexPerMeter), Math.ceil(tileSizeY * vertexPerMeter) );
			terrain.cellSize = new h2d.col.Point(tileSizeX / terrain.cellCount.x, tileSizeY / terrain.cellCount.y );
			terrain.heightMapResolution = new h2d.col.IPoint(terrain.cellCount.x + 1, terrain.cellCount.y + 1);
			terrain.refreshAllGrids();
			terrain.refreshAllTex();
			for( tile in terrain.tiles )
				tile.blendEdges();
			modified = true;
			var shared : hide.prefab.ContextShared = cast myContext.shared;
			@:privateAccess shared.scene.editor.view.save();
			trace("Terrain : " + name +  " is now up to date.");
			#end
		}
	}

	#if editor

	public function saveTextures( ctx : Context )  {
		if( !readyToSave(ctx) ) {
			throw "Failed to save terrain";
			return;
		}
		var shared : hide.prefab.ContextShared = cast myContext.shared;
		@:privateAccess shared.scene.setCurrent();
		clearSavedTextures(ctx);
		saveWeightTextures(ctx);
		saveHeightTextures(ctx);
		saveNormals(ctx);
		return;
	}

	function readyToSave( ctx : Context ) : Bool {
		var error = "Failed to save terrain : ";
		if( terrain == null ){
			trace(error + "terrain is null");
			return false;
		}
		if( terrain.surfaceArray == null ) {
			trace(error + "surfaceArray is null");
			return false;
		}
		if( terrain.surfaceArray.albedo == null || terrain.surfaceArray.albedo.isDisposed() ){
			trace(error + "surfaceArray.albedo is null");
			return false;
		}
		if( terrain.surfaceArray.normal == null || terrain.surfaceArray.normal.isDisposed() ){
			trace(error + "surfaceArray.normal is null");
			return false;
		}
		if( terrain.surfaceArray.pbr == null || terrain.surfaceArray.pbr.isDisposed() ){
			trace(error + "surfaceArray.pbr is null");
			return false;
		}

		for( tile in terrain.tiles ) {
			if( tile == null ) {
				trace(error + "tile is null");
				return false;
			}
			for( s in tile.surfaceWeights ) {
				if( s == null || s.isDisposed() ) {
					trace(error + "surfaceWeights "+ tile.surfaceWeights.indexOf(s) +" is null or disposed ");
					return false;
				}
			}
			if( tile.heightMap == null || tile.heightMap.isDisposed() ) {
					trace(error + "heightMap is null or disposed ");
					return false;
			}
			if( tile.surfaceIndexMap == null || tile.surfaceIndexMap.isDisposed() ) {
					trace(error + "surfaceIndexMap is null or disposed ");
					return false;
			}
			if( tile.surfaceWeightArray == null || tile.surfaceWeightArray.isDisposed() ) {
					trace(error + "surfaceWeightArray is null or disposed ");
					return false;
			}
		}
		return true;
	}

	function clearSavedTextures( ctx : Context ) {
		var datPath = new haxe.io.Path(ctx.shared.currentPath);
		datPath.ext = "dat";
		var fullPath = hide.Ide.inst.getPath(datPath.toString() + "/" + name);
		if( sys.FileSystem.isDirectory(fullPath) ) {
			var files = sys.FileSystem.readDirectory(fullPath);
			for( f in files )
				sys.FileSystem.deleteFile(fullPath + "/" + f);
		}
	}

	public function saveHeightTextures( ctx : Context ) {
		for( tile in terrain.tiles ) {
			var pixels : PixelsFloat = tile.heightMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "h";
			ctx.shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	public function saveNormals( ctx : Context ) {
		for( tile in terrain.tiles ) {
			if( tile.grid == null || tile.grid.normals == null || tile.grid.tangents == null ) continue;
			var normals = tile.grid.normals;
			var tangents = tile.grid.tangents;
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "n";
			var stride = 3 * 4 + 3 * 4; // Normal + Tangent
			var vertexCount = normals.length;
			var bytes = haxe.io.Bytes.alloc(vertexCount * stride);
			for( i in 0 ... normals.length ) {
				bytes.setFloat(i*stride, normals[i].x);
				bytes.setFloat(i*stride+4, normals[i].y);
				bytes.setFloat(i*stride+8, normals[i].z);
				bytes.setFloat(i*stride+12, tangents[i].x);
				bytes.setFloat(i*stride+16, tangents[i].y);
				bytes.setFloat(i*stride+20, tangents[i].z);
			}
			ctx.shared.savePrefabDat(fileName, "bin", name, bytes);
		}
	}

	public function saveWeightTextures( ctx : Context ) {
		var packedWeightsTex = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target], RGBA);
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

	#end

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		#if editor
		myContext = ctx;
		#end

		terrain = new TerrainMesh(ctx.local3d);
		terrain.tileSize = new h2d.col.Point(tileSizeX, tileSizeY);

		// Backward Compatibility
		if( oldHeightMapResolution != -1 && oldCellSize != -1 ) {
			terrain.heightMapResolution = new h2d.col.IPoint(oldHeightMapResolution, oldHeightMapResolution);
			var resolution = Math.max(0.1, oldCellSize);
			var cellCount = Math.ceil(Math.min(1000, tileSizeX / resolution));
			var finalCellSize = tileSizeX / cellCount;
			terrain.cellCount = new h2d.col.IPoint(cellCount, cellCount);
			terrain.cellSize = new h2d.col.Point(finalCellSize, finalCellSize);
			vertexPerMeter = terrain.cellCount.x / tileSizeX;
			needFormatUpdate = true;
		}
		else {
			terrain.cellCount = new h2d.col.IPoint(Math.ceil(tileSizeX * vertexPerMeter), Math.ceil(tileSizeY * vertexPerMeter) );
			terrain.cellSize = new h2d.col.Point(tileSizeX / terrain.cellCount.x, tileSizeY / terrain.cellCount.y );
			terrain.heightMapResolution = new h2d.col.IPoint(terrain.cellCount.x + 1, terrain.cellCount.y + 1);
		}
		if( oldWeightMapResolution != -1 ) {
			terrain.weightMapResolution = new h2d.col.IPoint(oldWeightMapResolution, oldWeightMapResolution);
			weightMapPixelPerMeter = oldWeightMapResolution / tileSizeX;
			needFormatUpdate = true;
		}
		else
			terrain.weightMapResolution = new h2d.col.IPoint(Math.round(tileSizeX * weightMapPixelPerMeter), Math.round(tileSizeY * weightMapPixelPerMeter));

		terrain.parallaxAmount = parallaxAmount;
		terrain.parallaxMinStep = parallaxMinStep;
		terrain.parallaxMaxStep = parallaxMaxStep;
		terrain.heightBlendStrength = heightBlendStrength;
		terrain.blendSharpness = blendSharpness;
		terrain.name = "terrain";

		ctx.local3d = terrain;
		ctx.local3d.name = name;

		updateInstance(ctx);
		return ctx;
	}

	override function make(ctx:Context):Context {
		ctx = super.make(ctx);
		initTerrain(ctx);
		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);

		#if editor
		terrain.parallaxAmount = parallaxAmount;
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

	#if editor
	override function makeInteractive( ctx : Context ) : h3d.scene.Interactive {
		return null;
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if( editor != null ) editor.setSelected(ctx, b);
		return true;
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
				<dt>Tile Size X</dt><dd><input type="range" min="1" max="100" value="0" field="tileSizeSetX"/></dd>
				<dt>Tile Size Y</dt><dd><input type="range" min="1" max="100" value="0" field="tileSizeSetY"/></dd>
				<dt>Vertex/Unit</dt><dd><input type="range" min="0.1" max="2" " value="0" field="vertexPerMeter"/></dd>
				<dt>Pixel/Unit</dt><dd><input type="range" min="0.1" max="2" value="0" field="weightMapPixelPerMeter"/></dd>
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
			tileSizeX = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSetX").range.value;
			tileSizeY = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSetY").range.value;
			weightMapPixelPerMeter = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapPixelPerMeter").range.value;
			vertexPerMeter = @:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="vertexPerMeter").range.value;
			terrain.weightMapResolution = new h2d.col.IPoint(Math.round(tileSizeX * weightMapPixelPerMeter), Math.round(tileSizeY * weightMapPixelPerMeter));
			terrain.weightMapResolution.x = Std.int(hxd.Math.max(1, terrain.weightMapResolution.x));
			terrain.weightMapResolution.y = Std.int(hxd.Math.max(1, terrain.weightMapResolution.y));
			terrain.tileSize = new h2d.col.Point(tileSizeX, tileSizeY);
			terrain.cellCount = new h2d.col.IPoint(Math.ceil(tileSizeX * vertexPerMeter), Math.ceil(tileSizeY * vertexPerMeter) );
			terrain.cellCount.x = Std.int(hxd.Math.max(1, terrain.cellCount.x));
			terrain.cellCount.y = Std.int(hxd.Math.max(1, terrain.cellCount.y));
			terrain.cellSize = new h2d.col.Point(tileSizeX / terrain.cellCount.x, tileSizeY / terrain.cellCount.y );
			terrain.heightMapResolution = new h2d.col.IPoint(terrain.cellCount.x + 1, terrain.cellCount.y + 1);
			terrain.refreshAllGrids();
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
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSetX").range.value = tileSizeX;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="tileSizeSetY").range.value = tileSizeY;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="weightMapPixelPerMeter").range.value = weightMapPixelPerMeter;
		@:privateAccess Lambda.find(ctx.properties.fields, f->f.fname=="vertexPerMeter").range.value = vertexPerMeter;
	}
	#end

	static var _ = Library.register("terrain", Terrain);
}