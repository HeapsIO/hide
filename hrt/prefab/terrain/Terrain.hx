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
@:access(hrt.prefab.terrain.Tile)
class Terrain extends Object3D {

	public var terrain : TerrainMesh;

	// Tile Param
	@:s public var tileSizeX : Float = 64.0;
	@:s public var tileSizeY : Float = 64.0;
	@:s public var vertexPerMeter : Float = 1.0;
	// Texture Param
	@:s public var weightMapPixelPerMeter : Float = 1.0;
	// Parallax Param
	@:s public var parallaxAmount = 0.0;
	@:s public var parallaxMinStep : Int = 1;
	@:s public var parallaxMaxStep : Int = 16;
	// Blend Param
	@:s public var heightBlendStrength : Float = 0.0;
	@:s public var blendSharpness : Float = 0.0;
	// Shadows Param
	@:s public var castShadows = false;
	// Data for binary save/load
	@:c var surfaceCount = 0;
	@:c var surfaceSize = 0;
	// Utility
	@:c var tmpSurfacesProps : Array<SurfaceProps> = [];
	var modified = false;

	#if editor
	var packWeight = new h3d.pass.ScreenFx(new PackWeight());
	var editor : hide.prefab.terrain.TerrainEditor;
	@:s public var showChecker = false;
	@:s public var autoCreateTile = false;
	@:s public var brushOpacity : Float = 1.0;
	#end

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.surfaces != null ) tmpSurfacesProps = obj.surfaces;
		surfaceCount = obj.surfaceCount == null ? 0 : obj.surfaceCount;
		surfaceSize = obj.surfaceSize == null ? 0 : obj.surfaceSize;
	}

	override function save( obj : Dynamic ) : Dynamic {
		super.save(obj);
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
			obj.surfaceCount = tmpSurfacesProps.length;
			if( surfaceSize != 0 ) obj.surfaceSize = surfaceSize;
			obj.surfaces = tmpSurfacesProps;
		}

		#if editor
		if( modified ) {
			modified = false;
			saveTextures();
		}
		#end

		return obj;
	}

	override function localRayIntersection(ray:h3d.col.Ray):Float {
		if( ray.lz > 0 )
			return -1; // only from top
		if( ray.lx == 0 && ray.ly == 0 ) {
			var z = terrain.getLocalHeight(ray.px, ray.py);
			if( z == null || z > ray.pz ) return -1;
			return ray.pz - z;
		}

		var b = new h3d.col.Bounds();
		for( t in terrain.tiles ) {
			var cb = t.getCachedBounds();
			if( cb != null )
				b.add(cb);
			else {
				b.addPos(t.x, t.y, -10000);
				b.addPos(t.x + terrain.cellSize.x * terrain.cellCount.x, t.y + terrain.cellSize.y * terrain.cellCount.y, 10000);
			}
		}

		var dist = b.rayIntersection(ray, false);
		if( dist < 0 )
			return -1;
		var pt = ray.getPoint(dist);
		var m = this.vertexPerMeter;
		var prevH = pt.z;
		while( true ) {
			pt.x += ray.lx * m;
			pt.y += ray.ly * m;
			pt.z += ray.lz * m;
			if( !b.contains(pt) )
				break;
			var h = terrain.getLocalHeight(pt.x, pt.y);
			if( pt.z < h ) {
				var k = 1 - (prevH - (pt.z - ray.lz * m)) / (ray.lz * m - (h - prevH));
				pt.x -= k * ray.lx * m;
				pt.y -= k * ray.ly * m;
				pt.z -= k * ray.lz * m;
				return pt.sub(ray.getPos()).length();
			}
			prevH = h;
		}
		return -1;
	}

	function loadTiles() {

		var resDir = shared.loadDir(name);
		if( resDir == null )
			return;

		var prevWatch = @:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH;
		@:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH = false;

		// Avoid texture alloc for unpacking
		var tmpPackedWeightTexture = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y);
		var bakeHeightAndNormalInGeometry = false;

		var heightData = [];
		var weightData = [];
		var normalData = [];
		var indexData = [];
		for( res in resDir ) {
			var fileInfos = res.name.split(".");
			var ext = fileInfos[1];
			var file = fileInfos[0];
			var coords = file.split("_");
			var x = Std.parseInt(coords[0]);
			var y = Std.parseInt(coords[1]);
			if( x == null || y == null ) continue;
			var type = coords[2];
			var data = { res : res, x : x, y : y, ext : ext };
			switch( type ) {
				case "n": normalData.push(data);
				case "h": heightData.push(data);
				case "w": weightData.push(data);
				case "i": indexData.push(data);
			}

			var tile = terrain.createTile(x, y, false);
			tile.material.shadows = castShadows;
			tile.material.mainPass.stencil = new h3d.mat.Stencil();
			tile.material.mainPass.stencil.setFunc(Always, 0x01, 0x01, 0x01);
			tile.material.mainPass.stencil.setOp(Keep, Keep, Replace);
		}

		// NORMAL
		for( nd in normalData ) {
			var t = terrain.getTile(nd.x, nd.y);
			var bytes = nd.res.entry.getBytes();
			var pixels = new hxd.Pixels(terrain.heightMapResolution.x, terrain.heightMapResolution.y, bytes, RGBA);
			t.normalMapPixels = pixels;
			if( !bakeHeightAndNormalInGeometry ) {
				t.refreshNormalMap();
				t.normalMap.uploadPixels(pixels);
				t.needNormalBake = false;
			}
		}

		// INDEX
		for( id in indexData ) {
			var t = terrain.getTile(id.x, id.y);
			if( t.surfaceIndexMap == null )
				@:privateAccess t.refreshIndexMap();
			if( id.ext == "png" ) { // Retro-compatibility
				var indexAsPNG = id.res.toTexture();
				h3d.pass.Copy.run(indexAsPNG, t.surfaceIndexMap);
				t.indexMapPixels = t.surfaceIndexMap.capturePixels();
				indexAsPNG.dispose();
			}
			else {
				var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution.x, terrain.weightMapResolution.y, id.res.entry.getBytes(), RGBA);
				t.indexMapPixels = pixels;
				t.surfaceIndexMap.uploadPixels(pixels);
			}
		}

		// WEIGHT
		var unpackWeight = new h3d.pass.ScreenFx(new UnpackWeight());
		for( wd in weightData ) {
			var t = terrain.getTile(wd.x, wd.y);
			var pixels : hxd.Pixels = new hxd.Pixels(terrain.weightMapResolution.x, terrain.weightMapResolution.y, wd.res.entry.getBytes(), RGBA);
			tmpPackedWeightTexture.uploadPixels(pixels);
			t.packedWeightMapPixel = pixels;

			// Notice that we need the surfaceIndexMap loaded before doing the unpacking
			var engine = h3d.Engine.getCurrent();
			#if editor
			// Unpack weight from RGBA texture into a array of texture of R8, and create the TextureArray
			if( t.surfaceWeights.length == 0 )
				@:privateAccess t.refreshSurfaceWeightArray();
			for( i in 0 ... t.surfaceWeights.length ) {
				engine.pushTarget(t.surfaceWeights[i]);
				unpackWeight.shader.indexMap = t.surfaceIndexMap;
				unpackWeight.shader.packedWeightTexture = tmpPackedWeightTexture;
				unpackWeight.shader.index = i;
				unpackWeight.render();
				engine.popTarget();
			}
			t.generateWeightTextureArray();
			#else
			// Unpack weight from RGBA texture directly into the TextureArray of R8
			t.generateWeightTextureArray();
			for( i in 0 ... terrain.surfaceArray.surfaceCount ) {
				engine.pushTarget(t.surfaceWeightArray, i);
				unpackWeight.shader.indexMap = t.surfaceIndexMap;
				unpackWeight.shader.packedWeightTexture = tmpPackedWeightTexture;
				unpackWeight.shader.index = i;
				unpackWeight.render();
				engine.popTarget();
			}
			#end
		}

		// HEIGHT
		for( hd in heightData ) {
			var t = terrain.getTile(hd.x, hd.y);
			var bytes = hd.res.entry.getBytes();
			var pixels = new hxd.Pixels(terrain.heightMapResolution.x, terrain.heightMapResolution.y, bytes, R32F);
			t.heightMapPixels = pixels;

			if( !bakeHeightAndNormalInGeometry ) {
				// Need heightmap texture for editing
				t.refreshHeightMap();
				t.heightMap.uploadPixels(pixels);
				t.needNewPixelCapture = false;
			}
		}

		// BAKE HEIGHT & NORMAL
		if( bakeHeightAndNormalInGeometry ) {
			for( t in terrain.tiles ) {
				t.createBigPrim();
			}
		}

		#if editor
		for( t in terrain.tiles ) {
			if( t == null ) {
				"Missing tile" + terrain.tiles.indexOf(t);
				continue;
			}
			if( t.heightMap == null ) trace("Missing heightmap for tile" + terrain.tiles.indexOf(t));
			if( t.normalMap == null ) trace("Missing normalmap for tile" + terrain.tiles.indexOf(t));
			if( t.surfaceIndexMap == null ) trace("Missing surfaceIndexMap for tile" + terrain.tiles.indexOf(t));
			if( t.surfaceWeightArray == null ) trace("Missing surfaceWeightArray for tile" + terrain.tiles.indexOf(t));
		}
		#end

		tmpPackedWeightTexture.dispose();
		@:privateAccess hxd.res.Image.ENABLE_AUTO_WATCH = prevWatch;
	}

	function loadSurfaces(onEnd : Void -> Void ) {
		for( surfaceProps in tmpSurfacesProps ) {
			var surface = terrain.addEmptySurface();
		}
		for( i in 0 ... tmpSurfacesProps.length ) {
			var surfaceProps = tmpSurfacesProps[i];
			var surface = terrain.getSurface(i);
			var albedo = shared.loadTexture(surfaceProps.albedo);
			var normal = shared.loadTexture(surfaceProps.normal);
			var pbr = shared.loadTexture(surfaceProps.pbr);
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
				if( onEnd != null )
					onEnd();
			}
			albedo.waitLoad(wait);
			normal.waitLoad(wait);
			pbr.waitLoad(wait);
		}
	}

	public function initTerrain() {

		terrain.createBigPrimitive();

		// Fix terrain being reloaded after a scene modification
		if( terrain.surfaceArray != null )
			return;


		var initDone = false;
		function waitAll() {

			if( initDone )
				return;

			for( surface in terrain.surfaces ) {
				if( surface == null || surface.albedo == null || surface.normal == null || surface.pbr == null )
					return;
			}
			terrain.generateSurfaceArray();

			loadTiles();

			initDone = true;
		}
		loadSurfaces(waitAll);
	}

	#if editor

	public function saveTextures()  {
		if( !readyToSave() ) {
			throw "Failed to save terrain";
			return;
		}
		@:privateAccess shared.scene.setCurrent();
		clearSavedTextures();
		saveWeightTextures();
		saveHeightTextures();
		saveNormalTextures();
		return;
	}

	function readyToSave() : Bool {
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

	function clearSavedTextures() {
		var datPath = new haxe.io.Path(shared.currentPath);
		datPath.ext = "dat";
		var fullPath = hide.Ide.inst.getPath(datPath.toString() + "/" + name);
		if( sys.FileSystem.isDirectory(fullPath) ) {
			var files = sys.FileSystem.readDirectory(fullPath);
			for( f in files )
				sys.FileSystem.deleteFile(fullPath + "/" + f);
		}
	}

	public function saveHeightTextures() {
		for( tile in terrain.tiles ) {
			var pixels = tile.heightMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "h";
			shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	public function saveNormalTextures() {
		for( tile in terrain.tiles ) {
			var pixels : hxd.Pixels = tile.normalMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "n";
			shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	public function saveWeightTextures() {
		var packedWeightsTex = new h3d.mat.Texture(terrain.weightMapResolution.x, terrain.weightMapResolution.y, [Target], RGBA);
		for( tile in terrain.tiles ) {
			h3d.Engine.getCurrent().pushTarget(packedWeightsTex);
			packWeight.shader.indexMap = tile.surfaceIndexMap;
			packWeight.shader.weightTextures = tile.surfaceWeightArray;
			packWeight.shader.weightCount = tile.surfaceWeights.length;
			packWeight.render();
			h3d.Engine.getCurrent().popTarget();

			var pixels = packedWeightsTex.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "w";
			shared.savePrefabDat(fileName, "bin", name, pixels.bytes);

			var pixels = tile.surfaceIndexMap.capturePixels();
			var fileName = tile.tileX + "_" + tile.tileY + "_" + "i";
			shared.savePrefabDat(fileName, "bin", name, pixels.bytes);
		}
	}

	#end

	function createTerrain( parent : h3d.scene.Object ) {
		return new TerrainMesh(parent);
	}

	override function makeObject(parent3d:h3d.scene.Object) : h3d.scene.Object {
		this.terrain = createTerrain(parent3d);
		terrain.tileSize = new h2d.col.Point(tileSizeX, tileSizeY);
		terrain.cellCount = new h2d.col.IPoint(Math.ceil(tileSizeX * vertexPerMeter), Math.ceil(tileSizeY * vertexPerMeter) );
		terrain.cellSize = new h2d.col.Point(tileSizeX / terrain.cellCount.x, tileSizeY / terrain.cellCount.y );
		terrain.heightMapResolution = new h2d.col.IPoint(terrain.cellCount.x + 1, terrain.cellCount.y + 1);
		terrain.weightMapResolution = new h2d.col.IPoint(Math.round(tileSizeX * weightMapPixelPerMeter), Math.round(tileSizeY * weightMapPixelPerMeter));
		terrain.parallaxAmount = parallaxAmount;
		terrain.parallaxMinStep = parallaxMinStep;
		terrain.parallaxMaxStep = parallaxMaxStep;
		terrain.heightBlendStrength = heightBlendStrength;
		terrain.blendSharpness = blendSharpness;
		terrain.name = "terrain";
		return terrain;
	}

	override function makeInstance() : Void {
		super.makeInstance();
		initTerrain();
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

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
	override function makeInteractive() : h3d.scene.Interactive {
		return null;
	}

	override function setSelected(b : Bool ) {
		if( editor != null ) editor.setSelected(b);
		return true;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "industry", name : "Terrain", isGround : true };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
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
		');

		ctx.properties.add(props, this, function(pname) {
			modified = true;
			ctx.onChange(this, pname);
		});

		var obj = {
			tileSize : tileSizeX,
			vertexes : vertexPerMeter,
			pixels : weightMapPixelPerMeter,
		};
		var options = new hide.Element('
		<div class="group" name="Quality"><dl>
			<dt>Tile Size (Units 3D)</dt><dd><input type="range" min="1" max="100" step="1" field="tileSize"/></dd>
			<dt>Vertexes and HeightMap<br/>(per Unit)</dt><dd><input type="range" min="0.1" max="2" field="vertexes"/></dd>
			<dt>Painting Weight Pixels<br/>(per Unit)</dt><dd><input type="range" min="0.1" max="2" field="pixels"/></dd>
			<div align="center"><input type="button" value="Apply" class="apply"/></div>
		</dl></div>
		');
		ctx.properties.add(options,obj);

		options.find('.apply').click(function(_) {
			tileSizeY = tileSizeX = obj.tileSize;
			TerrainResize.resize(this, new h2d.col.Point(tileSizeX, tileSizeY) );
			weightMapPixelPerMeter = obj.pixels;
			vertexPerMeter = obj.vertexes;
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
			if( editor != null ) {
				editor.refresh();
				@:privateAccess editor.blendEdges(terrain.tiles);
			}
			modified = true;
		});

		ctx.properties.add(new hide.Element('
			<div class="group" name="Debug"><dl>
				<dt>Show Grid</dt><dd><input type="checkbox" field="terrain.showGrid"/></dd>
				<dt>Mode</dt>
				<dd><select field="editor.renderMode">
						<option value="PBR">PBR</option>
						<option value="ShaderComplexity">Shader Complexity</option>
						<option value="Checker">Checker</option>
					</select></dd>
			</dl></div>
		'), this);
	}
	#end

	static var _ = Prefab.register("terrain", Terrain);
}