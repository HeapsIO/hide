package hrt.prefab.l3d;

// NOTE(ces) : Not Tested

enum abstract HeightMaPTexturePathKind(String) {
	var Albedo = "albedo";
	var Height = "height";
	var Normal = "normal";
	var SplatMap = "splatmap";
}

class HeightMapShader extends hxsl.Shader {
	static var SRC = {
		@:import h3d.shader.BaseMesh;

		@const var hasHeight : Bool;
		@const var hasNormal : Bool;

		@param var heightMap : Sampler2D;
		@param var heightMapFrag : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var heightScale : Float;
		@param var heightOffset : Vec2;
		@param var normalScale : Float;
		@param var cellSize : Vec2;
		@const var heightFlipX : Bool;
		@const var heightFlipY : Bool;

		@const var SplatCount : Int;
		@const var AlbedoCount : Int;
		@const(8) var SplatMode : Int;
		@const var albedoIsArray : Bool;
		@param var albedoTiling : Float;
		@param var albedos : Array<Sampler2D,AlbedoCount>;
		@param var albedoArray : Sampler2DArray;
		@param var albedoIndexes : Array<Vec4,AlbedoCount>;
		@param var splats : Array<Sampler2D,SplatCount>;

		@const var USE_BAKED_ALBEDO : Bool;
		@param var bakedAlbedo : Sampler2D;

		@input var input2 : { uv : Vec2 };

		@const var hasAlbedoProps : Bool;
		@param var albedoProps : Array<Vec4,AlbedoCount>;
		@param var albedoGamma : Float;

		@const var hasAlbedoNormals : Bool;
		@param var albedoNormals : Sampler2DArray;
		@param var albedoNormalsStrength : Float;
		@param var albedoRoughness : Float;

		var calculatedUV : Vec2;
		var heightUV : Vec2;
		var roughness : Float;

		function getPoint( dx : Float, dy : Float ) : Vec3 {
			var v = vec2(dx,dy);
			return vec3( cellSize * v , heightMapFrag.get(heightUV + heightOffset * v).r * heightScale - relativePosition.z);
		}

		function vertex() {
			calculatedUV = input2.uv;
			heightUV = calculatedUV;
			if( heightFlipX ) heightUV.x = 1 - heightUV.x;
			if( heightFlipY ) heightUV.y = 1 - heightUV.y;
			if( hasHeight ) {
				var z = heightMap.get(heightUV).x * heightScale;
				relativePosition.z = z;
			}
		}

		function setNormal(n:Vec3) {
			transformedNormal = (n.normalize() * global.modelView.mat3()).normalize();
		}

		function getAlbedo( index : Int, uv : Vec2 ) : Vec4 {
			var color = albedoIsArray ? albedoArray.get(vec3(uv,albedoIndexes[index].r)) : albedos[index].get(uv);
			if( albedoGamma != 1 )
				color = color.pow(albedoGamma.xxxx);
			return color;
		}

		function splat( index : Int, amount : Float ) : Vec4 {
			if( index >= AlbedoCount || amount <= 0 )
				return vec4(0.);
			else if( hasAlbedoProps ) {
				var p = albedoProps[index];
				return getAlbedo(index, calculatedUV * p.w) * vec4(p.rgb,1) * amount;
			} else
				return getAlbedo(index, calculatedUV * albedoTiling) * amount;
		}

		function fragment() {
			if( hasNormal ) {
				var n = unpackNormal(normalMap.get(calculatedUV));
				n = n.normalize();
				n.xy *= normalScale;
				setNormal(n);
			} else {
				var px0 = getPoint(-1,0);
				var py0 = getPoint(0, -1);
				var px1 = getPoint(1, 0);
				var py1 = getPoint(0, 1);
				var n = px1.cross(py1) + py1.cross(px0) + px0.cross(py0) + py0.cross(px1);
				n.xy *= normalScale;
				setNormal(n);
			}
			if ( USE_BAKED_ALBEDO ) {
				pixelColor = bakedAlbedo.getLod(calculatedUV, 0);
			} else if( SplatCount > 0 ) {
				var color = vec4(0.);
				if( SplatMode == 3 || SplatMode == 4 )
					color = splat(0,1);
				@unroll for( i in 0...SplatCount ) {
					var s = splats[i].getLod(calculatedUV,0);
					switch( SplatMode ) {
					case 0:
						color += splat(i*3, s.r);
						color += splat(i*3+1, s.g);
						color += splat(i*3+2, s.b);
					case 1:
						color += splat(i*4, s.r);
						color += splat(i*4+1, s.g);
						color += splat(i*4+2, s.b);
						color += splat(i*4+3, s.a);
					case 2:
						var i1 = int(s.r*256);
						var i2 = int(s.g*256);
						color += splat(i1,s.b);
						color += splat(i2,s.a);
						if( hasAlbedoNormals ) {
							var uv1 = calculatedUV * albedoProps[i1].w;
							var uv2 = calculatedUV * albedoProps[i2].w;
							var normal1 = albedoNormals.get(vec3(uv1,albedoIndexes[i1].r));
							var normal2 = albedoNormals.get(vec3(uv2,albedoIndexes[i2].r));
							var med = mix(normal1,normal2,s.a);
							var nf = unpackNormal(med);
							nf.xy *= albedoNormalsStrength;
							nf = nf.normalize();

							var n = transformedNormal;
							var tanX = vec3(1,0,0);
							var tanY = transformedNormal.cross(tanX);
							transformedNormal = (nf.x * tanX + nf.y * tanY + nf.z * n).normalize();

							roughness *= 1 - med.a * med.a * albedoRoughness;
						}
					case 3:
						color = mix(color, splat(i*3+1, 1), s.r);
						color = mix(color, splat(i*3+2, 1), s.g);
						color = mix(color, splat(i*3+3, 1), s.b);
					case 4:
						color = mix(color, splat(i*4+1, 1), s.r);
						color = mix(color, splat(i*4+2, 1), s.g);
						color = mix(color, splat(i*4+3, 1), s.b);
						color = mix(color, splat(i*4+4, 1), s.a);
					}
				}
				color.a = 1;
				pixelColor = color;
			} else {
				pixelColor = getAlbedo(0, calculatedUV);
			}
		}

	};
}

private class HeightMapTileBakeShader extends h3d.shader.ScreenShader {

	static var SRC = {
		@const var SplatCount : Int;
		@const var AlbedoCount : Int;
		@const(8) var SplatMode : Int;
		@const var albedoIsArray : Bool;
		@param var albedoTiling : Float;
		@param var albedos : Array<Sampler2D,AlbedoCount>;
		@param var albedoArray : Sampler2DArray;
		@param var albedoIndexes : Array<Vec4,AlbedoCount>;
		@param var splats : Array<Sampler2D,SplatCount>;
		@const var hasAlbedoProps : Bool;
		@param var albedoProps : Array<Vec4,AlbedoCount>;
		@param var albedoGamma : Float;

		@input var input2 : { uv : Vec2 };

		// Output
		var albedoOutput : Vec4;

		function vertex() {
			calculatedUV = input.uv;
			output.position = vec4(uvToScreen(calculatedUV), 0, 1);
			output.position.y *= flipY;
		}

		function getAlbedo( index : Int, uv : Vec2 ) : Vec4 {
			var color = albedoIsArray ? albedoArray.get(vec3(uv,albedoIndexes[index].r)) : albedos[index].get(uv);
			if( albedoGamma != 1 )
				color = color.pow(albedoGamma.xxxx);
			return color;
		}

		function splat( index : Int, amount : Float ) : Vec4 {
			if( index >= AlbedoCount || amount <= 0 )
				return vec4(0.);
			else if( hasAlbedoProps ) {
				var p = albedoProps[index];
				return getAlbedo(index, calculatedUV * p.w) * vec4(p.rgb,1) * amount;
			} else
				return getAlbedo(index, calculatedUV * albedoTiling) * amount;
		}

		function __init__fragment() {
			if( SplatCount > 0 ) {
				var color = vec4(0.);
				@unroll for( i in 0...SplatCount ) {
					var s = splats[i].getLod(calculatedUV,0);
					switch( SplatMode ) {
					case 0:
						color += splat(i*4, s.r);
						color += splat(i*4+1, s.g);
						color += splat(i*4+2, s.b);
						color += splat(i*4+3, s.a);
					case 1:
						color += splat(i*3, s.r);
						color += splat(i*3+1, s.g);
						color += splat(i*3+2, s.b);
					case 2:
						var i1 = int(s.r*256);
						var i2 = int(s.g*256);
						color += splat(i1,s.b);
						color += splat(i2,s.a);
					}
				}
				color.a = 1;
				pixelColor = color;
			} else {
				pixelColor = getAlbedo(0, calculatedUV);
			}
			albedoOutput = pixelColor;
		}

	};
}

class HeightMapTile {

	public var tx(default,null) : Int;
	public var ty(default,null) : Int;
	public var bounds(default, null) : h3d.col.Bounds;
	public var root(default,null) : h3d.scene.Mesh;
	public var albedoTex : h3d.mat.Texture;

	var hmap : HeightMap;
	var height : hxd.Pixels;
	var shader : HeightMapShader;

	public function new(hmap, tx, ty) {
		this.hmap = hmap;
		this.tx = tx;
		this.ty = ty;
		bounds = h3d.col.Bounds.fromValues(tx * hmap.size, ty * hmap.size, hmap.minZ, hmap.size, hmap.size, hmap.maxZ - hmap.minZ);
	}

	public function remove() {
		if( root != null ) {
			root.remove();
			root = null;
		}
		if ( albedoTex != null )
			albedoTex.dispose();
	}

	public function isEmpty() {
		if( tx == 0 && ty == 0 && hmap.sizeX == 0 && hmap.sizeY == 0 && !hmap.autoSize )
			return false;
		getHeight();
		return height.width == 1;
	}

	public function getHeight() {
		if( height == null ) {
			for( t in hmap.textures )
				if( t.kind == Height && t.enable && t.path != null ) {
					var path = resolveTexturePath(t.path);
					if( path == t.path && (tx != 0 || ty != 0) ) continue;
					height = try hxd.res.Loader.currentInstance.load(path).toImage().getPixels() catch( e : hxd.res.NotFound )
					#if editor try hxd.res.Any.fromBytes(path, sys.io.File.getBytes(hide.Ide.inst.getPath(path))).toImage().getPixels() catch( e : Dynamic ) #end
					null;
					break;
				}
			if( height == null ) height = hxd.Pixels.alloc(1, 1, R32F);
			height.convert(R32F);
		}
		return height;
	}

	public function createShadows(mesh:HeightMapMesh) {
		shadows = new h3d.scene.Mesh(@:privateAccess mesh.shadowGrid, root);
		shadows.material.shadows = false;
		shadows.material.mainPass.setPassName("shadow");
		var smat = shadows.material;
		@:bypassAccessor smat.castShadows = true; // trigger DirShadowMap
		shadows.material.mainPass.addShader(shader);
	}

	var shadows : h3d.scene.Mesh;
	@:access(hrt.prefab.l3d.HeightMapMesh)
	public function create(mesh:HeightMapMesh) {
		if( root != null ) throw "assert";
		root = new h3d.scene.Mesh(mesh.grid);
		root.material.mainPass.setPassName("terrain");
		root.material.shadows = false;
		root.x = hmap.size * tx;
		root.y = hmap.size * ty;

		inline function getTextures(k) return hmap.getTextures(k,tx,ty);
		var htex = getTextures(Height)[0];
		var splat = getTextures(SplatMap);
		var normal = getTextures(Normal)[0];

		shader = root.material.mainPass.addShader(new HeightMapShader());
		if ( mesh.hmap.castShadows )
			createShadows(mesh);
		shader.hasHeight = htex != null;
		shader.heightMap = shader.heightMapFrag = htex;
		shader.hasNormal = normal != null;
		shader.normalMap = normal;
		shader.heightScale = hmap.getHScale();
		shader.normalScale = hmap.heightScale * hmap.normalScale;
		var qsize = Math.pow(2,4 - hmap.quality);
		shader.cellSize.set(mesh.grid.cellWidth / qsize,mesh.grid.cellHeight / qsize);
		shader.heightFlipX = hmap.heightFlipX;
		shader.heightFlipY = hmap.heightFlipY;
		if( htex != null ) shader.heightOffset.set( (hmap.heightFlipX ? -1 : 1) / htex.width, (hmap.heightFlipY ? -1 : 1) / htex.height);

		shader.SplatCount = splat.length;
		shader.albedoIsArray = false;
		shader.SplatMode = switch( hmap.splatMode ) {
		case Weights3: 0;
		case Weights4: 1;
		case I1I2W1W2: shader.albedoIsArray = true; 2;
		case BaseWeights3: 3;
		case BaseWeights4: 4;
		}

		shader.albedoTiling = hmap.albedoTiling;
		shader.albedoGamma = hmap.albedoGamma;
		shader.splats = splat;
		for( t in splat ) t.filter = hmap.splatNearest ? Nearest : Linear;

		if( shader.albedoIsArray ) {
			var arr = hmap.getTextureArray(Albedo);
			shader.albedoArray = arr.texture;
			shader.albedoIndexes = [for( i in arr.indexes ) new h3d.Vector4(i)];
			shader.AlbedoCount = arr.indexes.length;
			if( hmap.albedoNormals > 0 ) {
				shader.hasAlbedoNormals = true;
				shader.albedoNormals = hmap.getTextureArray(Normal).texture;
				shader.albedoNormalsStrength = hmap.albedoNormals;
				shader.albedoRoughness = hmap.albedoRoughness;
			}
		} else {
			var albedo = getTextures(Albedo);
			if( albedo.length == 0 )
				albedo = [h3d.mat.Texture.fromColor(0x808080)];
			shader.AlbedoCount = albedo.length;
			shader.albedos = albedo;
		}

		shader.albedoProps = hmap.getAlbedoProps();
		shader.hasAlbedoProps = shader.albedoProps.length > 0;

		shader.USE_BAKED_ALBEDO = false;

		if ( hmap.bakedAlbedo )
			bake();
	}

	public function bake() {
		albedoTex = new h3d.mat.Texture(hmap.bakedAlbedoSize, hmap.bakedAlbedoSize, [Target]);
		albedoTex.preventAutoDispose();

		// Should use waitLod on splat textures to wait for async loading if any.
		var ss = new h3d.pass.ScreenFx(new HeightMapTileBakeShader(), [Value("albedoOutput")]);
		ss.shader.SplatCount = shader.SplatCount;
		ss.shader.albedoIsArray = shader.albedoIsArray;
		ss.shader.SplatMode = shader.SplatMode;
		ss.shader.albedoTiling = shader.albedoTiling;
		ss.shader.albedoGamma = shader.albedoGamma;
		ss.shader.splats = shader.splats;
		ss.shader.AlbedoCount = shader.AlbedoCount;
		if( shader.albedoIsArray ) {
			ss.shader.albedoArray = shader.albedoArray;
			ss.shader.albedoIndexes = shader.albedoIndexes;
		} else {
			ss.shader.albedos = shader.albedos;
		}
		ss.shader.albedoProps = shader.albedoProps;
		ss.shader.hasAlbedoProps = shader.hasAlbedoProps;

		var engine = h3d.Engine.getCurrent();
		engine.pushTarget(albedoTex);
		ss.render();
		engine.popTarget();

		shader.USE_BAKED_ALBEDO = true;
		shader.bakedAlbedo = albedoTex;
	}

	inline function resolveTexturePath( path : String ) {
		return hmap.resolveTexturePath(path, tx, ty);
	}

}

class HeightMapMesh extends h3d.scene.Object {

	var hmap : HeightMap;
	var grid : HeightGrid;
	var shadowGrid : HeightGrid;

	public function new(hmap, ?parent) {
		super(parent);
		this.hmap = hmap;
	}

	override function onRemove() {
		super.onRemove();
		hmap.cleanCache();
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		super.sync(ctx);
		if( ctx.debugCulling )
			return;

		if( hmap.sizeX == 0 && hmap.sizeY == 0 && !hmap.autoSize ) {
			checkTile(ctx,0,0);
			return;
		}

		var r = h3d.col.Ray.fromPoints(ctx.camera.unproject(0,0,0).toPoint(), ctx.camera.unproject(0,0,1).toPoint());
		var pt0 = r.intersect(h3d.col.Plane.Z(0));
		var x0 = Math.round(pt0.x / hmap.size);
		var y0 = Math.round(pt0.y / hmap.size);

		// spiral for-loop
		var dx = 0, dy = 0, d = 1, m = 1, out = 0;
		while( true ) {
			var xyOut = true;
			while( m > 2 * dx * d ) {
				if( checkTile(ctx,dx+x0,dy+y0) ) xyOut = false;
				dx += d;
			}
			while( m > 2 * dy * d ) {
				if( checkTile(ctx,dx+x0,dy+y0) ) xyOut = false;
				dy += d;
			}
			if( xyOut ) {
				out++;
				if( out == 2 ) break;
			} else
				out = 0;
			d = -d;
			m++;
		}
	}

	public dynamic function onTileReady( t : HeightMapTile ) {
	}

	public dynamic function isAssetFiltered( obj : h3d.scene.World.WorldModel, pos : h3d.Matrix ) {
		return false;
	}

	function checkTile( ctx : h3d.scene.RenderContext, x : Int, y : Int ) {
		var t = hmap.getTile(x,y);
		if( !ctx.camera.frustum.hasBounds(t.bounds) || t.isEmpty() ) {
			if( t.root != null ) t.root.visible = false;
			return hmap.isTileInBounds(x, y);
		}
		if( t.root != null )
			t.root.visible = true;
		else
			initTile(t);
		return true;
	}

	public function initTile( t : HeightMapTile ) {
		if( t.root != null ) return;
		t.create(this);
		addChild(t.root);
		onTileReady(t);
	}

	public function init() {
		var htex = hmap.getTextures(Height, 0, 0)[0];
		var size = hmap.size;
		var width = htex == null ? Std.int(size) : Math.ceil(htex.width * hmap.heightPrecision);
		var height = htex == null ? Std.int(size) : Math.ceil(htex.height * hmap.heightPrecision);
		var swidth = width >> (4 - hmap.shadowQuality);
		var sheight = width >> (4 - hmap.shadowQuality);
		width >>= (4 - hmap.quality);
		height >>= (4 - hmap.quality);
		if( width < 4 ) width = 4;
		if( height < 4 ) height = 4;
		#if js
		if( width > 4096 ) width = 4096;
		if( height > 4096 ) height = 4096;
		#end
		var cw = size/width, ch = size/height;
		if( grid == null || grid.width != width || grid.height != height || grid.cellWidth != cw || grid.cellHeight != ch ) {
			grid = new HeightGrid(width,height,cw,ch);
			grid.zMin = hmap.minZ;
			grid.zMax = hmap.maxZ;
			grid.addUVs();
			grid.addNormals();
		}
		var cw = size/swidth, ch = size/sheight;
		if( shadowGrid == null || shadowGrid.width != swidth || shadowGrid.height != sheight || shadowGrid.cellWidth != cw || shadowGrid.cellHeight != ch ) {
			if( swidth == width )
				shadowGrid = grid;
			else {
				shadowGrid = new HeightGrid(swidth,sheight,cw,ch);
				shadowGrid.zMin = hmap.minZ;
				shadowGrid.zMax = hmap.maxZ;
				shadowGrid.addUVs();
			}
		}
	}

}

enum abstract SplatMode(String) {
	var Weights3;
	var Weights4;
	var BaseWeights3;
	var BaseWeights4;
	var I1I2W1W2;
}

@:allow(hrt.prefab.l3d)
class HeightMap extends Object3D {

	#if editor
	var view : hide.comp.Component;
	#end
	var tilesCache : Map<Int,HeightMapTile> = new Map();
	var emptyTile : HeightMapTile;
	@:c var textures : Array<{ path : String, kind : HeightMaPTexturePathKind, enable : Bool, ?props : { color : Int, scale : Float } }> = [];
	@:s var size = 128.;
	@:s var heightScale = 0.2;
	@:s var heightFlipX = false;
	@:s var heightFlipY = false;
	@:s var normalScale = 1.;
	@:s var heightPrecision = 1.;
	@:s var minZ = -10;
	@:s var maxZ = 30;
	@:s public var quality(get, default) = 4;
	@:s public var bakedAlbedo = false;
	@:s var bakedAlbedoSize = 2048;
	function get_quality() {

		#if editor
		if (view != null) {
			if (@:privateAccess view.getDisplayState("graphicsFilters/highQuality") != false) {
				return quality;
			}
			else {
				return 1;
			}
		}
		#end
		return quality;

	}
	@:s public var shadowQuality(get, default) = 4;
	function get_shadowQuality() {

		#if editor
		if (view != null) {
			if (@:privateAccess view.getDisplayState("graphicsFilters/highQuality") != false) {
				return shadowQuality;
			}
			else {
				return 0;
			}
		}
		#end
		return shadowQuality;

	}
	@:s public var castShadows = true;
	public function set_castShadows(v : Bool) {
		castShadows = v;
		for ( t in tilesCache ) {
			var shadows = @:privateAccess t.shadows;
			if ( !castShadows ) {
				if ( shadows != null ) {
					shadows.remove();
					shadows = null;
				}
			} else {
				if ( shadows == null ) {
					if ( t.root != null && t.root.parent != null )
						t.createShadows(cast(t.root.parent, HeightMapMesh));
				}
			}
		}
		return castShadows;
	}
	@:s var sizeX = 0;
	@:s var sizeY = 0;
	@:s var minTileX = 0;
	@:s var minTileY = 0;
	@:s var autoSize = false;
	@:s var albedoTiling = 1.;
	@:s var albedoGamma = 1.;
	@:s var albedoColorGamma = 1.;
	@:s var splatNearest = false;
	@:s var splatMode : SplatMode = Weights4;
	@:s var albedoNormals : Float = 0.;
	@:s var albedoRoughness : Float = 0.;

	// todo : instead of storing the context, we should find a way to have a texture loader
	var albedoProps : Array<h3d.Vector4>;
	var texArrayCache : Map<HeightMaPTexturePathKind, { texture : h3d.mat.TextureArray, indexes : Array<Int> }>;

	override function save():Dynamic {
		var o : Dynamic = super.save();
		o.textures = [for( t in textures ) {
			var v : Dynamic = { path : t.path, kind : t.kind };
			if( !t.enable ) v.enable = false;
			if( t.props != null ) v.props = t.props;
			v;
		}];
		o.quality = @:bypassAccessor quality;
		o.shadowQuality = @:bypassAccessor shadowQuality;
		return o;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		textures = [for( o in (obj.textures:Array<Dynamic>) ) { path : o.path, kind : o.kind, enable : o.enable == null ? true : o.enable, props : o.props }];
	}

	override function copy(o:Prefab) {
		super.copy(o);
		var p : HeightMap = cast o;
		this.textures = p.textures;
	}

	function getAlbedoProps() : Array<h3d.Vector4> {
		if( albedoProps != null )
			return albedoProps;
		var hasProps = false;
		for( t in textures )
			if( t.kind == Albedo && t.props != null )
				hasProps = true;
		if( !hasProps ) {
			albedoProps = [];
			return albedoProps;
		}
		albedoProps = [for( t in textures ) if( t.kind == Albedo ) t.props == null ? new h3d.Vector4(1,1,1,albedoTiling) : {
			var v = h3d.Vector4.fromColor(t.props.color);
			v.r = Math.pow(v.r,albedoColorGamma);
			v.g = Math.pow(v.g,albedoColorGamma);
			v.b = Math.pow(v.b,albedoColorGamma);
			v.a = t.props.scale * albedoTiling;
			v;
		}];
		return albedoProps;
	}

	public static var INVALID_Z = 1e128;

	public function getZ( x : Float, y : Float ) : Float {
		var rx = x / size;
		var ry = y / size;
		var tx = Math.floor(rx);
		var ty = Math.floor(ry);
		var curMap = getTile(tx, ty).getHeight();
		if( curMap == null )
			return INVALID_Z;
		var w = curMap.width;
		var ix = Std.int( (rx - tx) * w );
		var iy = Std.int( (ry - ty) * w );
		var h = curMap.bytes.getFloat((ix+iy*w) << 2);
		h *= getHScale();
		return h;
	}

	override function localRayIntersection(ray:h3d.col.Ray):Float {
		if( ray.lz > 0 )
			return -1; // only from top
		if( ray.lx == 0 && ray.ly == 0 ) {
			var z = getZ(ray.px, ray.py);
			if( z == INVALID_Z || z > ray.pz ) return -1;
			return ray.pz - z;
		}
		var dist = 0.;
		if( ray.pz > maxZ ) {
			if( ray.lz == 0 )
				return -1;
			dist = (maxZ - ray.pz) / ray.lz;
		}
		var pt = ray.getPoint(dist);
		if( pt.z < minZ )
			return -1;

		var prim = @:privateAccess cast(local3d, HeightMapMesh).grid;
		var m = hxd.Math.min(prim.cellWidth, prim.cellHeight) * 0.5;
		var curX = -1, curY = -1, curMap = null, offX = 0., offY = 0., cw = 0., ch = 0.;
		var prevH = pt.z;
		var hscale = getHScale();

		while( true ) {
			pt.x += ray.lx * m;
			pt.y += ray.ly * m;
			pt.z += ray.lz * m;
			if( pt.z < minZ )
				return -1;
			var px = Math.floor(pt.x / size);
			var py = Math.floor(pt.y / size);
			if( px != curX || py != curY ) {
				curX = px;
				curY = py;
				offX = -px * size;
				offY = -py * size;
				var t = getTile(px, py);
				curMap = t.getHeight();
				if( t.isEmpty() )
					curMap = null;
				else {
					cw = curMap.width / size;
					ch = curMap.height / size;
				}
			}
			if( curMap == null )
				continue;
			var ix = Std.int((pt.x + offX)*cw);
			var iy = Std.int((pt.y + offY)*ch);
			var h = curMap.bytes.getFloat( (ix + iy * curMap.width) << 2 );
			h *= hscale;
			if( pt.z < h ) {
				// todo : fix interpolation using getZ dichotomy
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

	public inline function isTileInBounds(x : Int, y : Int) {
		return x >= minTileX && y >= minTileY && x < sizeX + minTileX && y < sizeY + minTileY;
	}

	function getTile( x : Int, y : Int ) {
		if( (sizeX > 0 && sizeY > 0 && !isTileInBounds(x, y)) || (sizeX == 0 && sizeY == 0 && (x != 0 || y != 0) && !autoSize) ) {
			if( emptyTile == null )
				emptyTile = new HeightMapTile(this, -minTileX - 1, -minTileY - 1);
			return emptyTile;
		}
		var id = x - minTileX + (y - minTileY) * 65535;
		var t = tilesCache[id];
		if( t != null )
			return t;
		t = new HeightMapTile(this, x, y);
		tilesCache[id] = t;
		return t;
	}

	function resolveTexturePath( path : String, tx : Int, ty : Int ) {
		if( tx != 0 || ty != 0 ) {
			var parts = path.split("0");
			switch( parts.length ) {
			case 2:
				path = tx + parts[0] + ty + parts[1];
			case 3:
				path = parts[0] + tx + parts[1] + ty + parts[2];
			default:
				// pattern not recognized - should contain 2 zeroes
			}
		}
		return path;
	}

	function getTextures( k : HeightMaPTexturePathKind, tx : Int, ty : Int ) {
		var tl = [];
		for( t in textures ) {
			var b = t.kind == k && t.path != null && t.enable;
			#if editor
			if (view != null)
				b = b && @:privateAccess view.getDisplayState("graphicsFilters/"+Std.string(k)) != false;
			#end
			if( b ) {
				var path = resolveTexturePath(t.path,tx,ty);
				tl.push(shared.loadTexture(path));
			}
		}
		return tl;
	}

	function cleanCache() {
		if( texArrayCache == null ) return;
		for( k in texArrayCache )
			k.texture.dispose();
		texArrayCache = null;
	}

	function getTextureArray( k : HeightMaPTexturePathKind ) {
		if( texArrayCache == null ) texArrayCache = new Map();
		var arr = texArrayCache.get(k);
		if( arr != null && !arr.texture.isDisposed() )
			return arr;
		#if editor
		var tl = switch( k ) {
		case Albedo: getTextures(k, 0, 0);
		case Normal:
			var tl = [];
			for( t in textures )
				if( t.kind == Albedo && t.path != null && t.enable ) {
					var path = new haxe.io.Path(t.path);
					path.file = path.file.split("_Albedo").join("");
					path.file += "_Normal";
					tl.push(shared.loadTexture(path.toString()));
				}
			tl;
		default: throw "assert";
		}
		if( tl.length == 0 ) tl = [h3d.mat.Texture.fromColor(k == Normal ? 0x8080FF : 0xFF00FF)];
		var indexes = [];
		var layers = [];
		for( t in tl ) {
			var idx = layers.indexOf(t);
			if( idx < 0 ) {
				idx = layers.length;
				layers.push(t);
			}
			indexes.push(idx);
		}
		var tex = new h3d.mat.TextureArray(layers[0].width, layers[0].height, layers.length, [Target], switch( layers[0].format ) {
		case S3TC(_): RGBA;
		case fmt: fmt;
		});
		tex.realloc = function() {
			for( i => t in layers )
				h3d.pass.Copy.run(t, tex, null, null, i);
		};
		#else
		var pl = switch ( k ) {
		case Albedo:
			var pl = [];
			for ( t in textures ) {
				if ( t.kind != Albedo || t.path == null || !t.enable ) continue;
				var image = hxd.res.Loader.currentInstance.load(t.path).toImage();
				pl.push(image.getPixels());
			}
			pl;
		case Normal:
			var pl = [];
			for ( t in textures ) {
				if ( t.kind != Albedo || t.path == null || !t.enable ) continue;
				var path = new haxe.io.Path(t.path);
				path.file = path.file.split("_Albedo").join("");
				path.file += "_Normal";
				var image = hxd.res.Loader.currentInstance.load(path.toString()).toImage();
				pl.push(image.getPixels());
			}
			pl;
		default: throw "assert";
		}
		var defaultTexture = null;
		if( pl.length == 0 ) defaultTexture = h3d.mat.Texture.fromColor(k == Normal ? 0x8080FF : 0xFF00FF);
		var indexes = [];
		var layers = [];
		for( p in pl ) {
			var idx = layers.indexOf(p);
			if( idx < 0 ) {
				idx = layers.length;
				layers.push(p);
			}
			indexes.push(idx);
		}
		var tex;
		if ( defaultTexture != null )
			tex = new h3d.mat.TextureArray(defaultTexture.width, defaultTexture.height, 1, defaultTexture.format);
		else
			tex = new h3d.mat.TextureArray(layers[0].width, layers[0].height, layers.length, layers[0].format);
		tex.realloc = function() {
			if ( defaultTexture != null )
				h3d.pass.Copy.run(defaultTexture, tex, null, null, 0);
			else
				for( i => t in layers )
					tex.uploadPixels(layers[i], 0, i );
		};
		#end
		tex.realloc();
		tex.wrap = Repeat;
		arr = { texture : tex, indexes : indexes };
		texArrayCache.set(k, arr);
		return arr;
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		var mesh = new HeightMapMesh(this, parent3d);
		return mesh;
	}

	override function updateInstance( ?propName : String ) {

		#if editor
		if( (propName == "albedoTiling" || propName == "albedoColorGamma") && albedoProps != null ) {
			updateAlbedoProps();
			return;
		}
		if (view == null) {
			if (shared != null)
				view = shared.scene.editor.view;
		}
		#end

		albedoProps = null;
		cleanCache();
		super.updateInstance(propName);

		for( t in tilesCache )
			t.remove();
		tilesCache = new Map();
		var mesh = cast(local3d,HeightMapMesh);
		mesh.init();
	}

	function getHScale() {
		return heightScale * size * 0.1;
	}

	#if editor

	override function setSelected(b:Bool):Bool {
		return true;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "industry", name : "HeightMap", isGround : true };
	}

	function updateAlbedoProps() {
		var prev = albedoProps;
		while( prev.length > 0 ) prev.pop();
		albedoProps = null;
		for( x in getAlbedoProps() )
			prev.push(x);
		albedoProps = prev;
	}

	override function edit(ectx:hide.prefab.EditContext) {
		super.edit(ectx);
		var hasSplat = false;
		for( t in textures )
			if( t.kind == SplatMap ) {
				hasSplat = true;
				break;
			}
		var props = new hide.Element('
		<div>
			<div class="group" name="View">
			<dl>
				<dt>Size</dt><dd><input type="range" min="0" max="1000" value="128" field="size"/></dd>
				<dt>Height Scale</dt><dd><input type="range" min="0" max="1" field="heightScale"/></dd>
				<dt>Height Precision</dt><dd><input type="range" min="0.1" max="1" field="heightPrecision"/></dd>
				<dt>Height Flip</dt><dd>
					<label><input type="checkbox"field="heightFlipX"/> X</label>
					<label><input type="checkbox"field="heightFlipY"/> Y</label>
				</dd>
				<dt>Normal Scale</dt><dd><input type="range" min="0" max="2" field="normalScale"/></dd>
				<dt>MinZ</dt><dd><input type="range" min="-1000" max="0" field="minZ"/></dd>
				<dt>MaxZ</dt><dd><input type="range" min="0" max="1000" field="maxZ"/></dd>
				<dt>Quality</dt><dd><input type="range" min="0" max="4" field="quality" step="1"/></dd>
				<dt>Cast Shadows</dt><dd><input type="checkbox" field="castShadows"/></dd>
				<dt>Shadows Quality</dt><dd><input type="range" min="0" max="4" field="shadowQuality" step="1"/></dd>
			'+(hasSplat ? '
				<dt>Albedo Tiling</dt><dd><input type="range" field="albedoTiling"/>
				<dt>Splat Mode</dt><dd>
					<select style="width:120px" field="splatMode">
						<option value="Weights4">Weights4
						<option value="Weights3">Weights3
						<option value="I1I2W1W2">I1I2W1W2
						<option value="BaseWeights4">BaseWeights4
						<option value="BaseWeights3">BaseWeights3
					</select>
					<label><input type="checkbox" field="splatNearest"/> Nearest</label>
				</dd>
				<dt>Albedo Normals</dt><dd><input type="range" min="0" max="1" field="albedoNormals"/></label>
				<dt>Albedo Roughness</dt><dd><input type="range" min="0" max="1" field="albedoRoughness"/></label>
			': '')+'
				<dt>Gamma</dt><dd><input type="range" min="0" max="4" field="albedoGamma"/></dd>
				<dt>Gamma Color</dt><dd><input type="range" min="0" max="4" field="albedoColorGamma"/></dd>
				<dt>Fixed Size</dt><dd><input type="number" style="width:50px" field="sizeX"/><input type="number" style="width:50px" field="sizeY"/> <label><input type="checkBox" field="autoSize"> Auto</label></dd>
				<dt>Min Tile X</dt><dd><input type="range" min="-1000" max="0" field="minTileX"/></dd>
				<dt>Min Tile Y</dt><dd><input type="range" min="-1000" max="0" field="minTileY"/></dd>
				<dt>Bake Albedo</dt><dd><input type="checkbox" field="bakedAlbedo"/></dd>
				<dt>Baked Albedo Size</dt><dd><input type="range" step="2" field="bakedAlbedoSize"/></dd>
			</dl>
			</div>
			<div class="group" name="Textures">
				<ul id="tex"></ul>
			</div>
		</div>
		');

		var list = props.find("ul#tex");
		ectx.properties.add(props,this, (_) -> updateInstance());
		for( tex in textures ) {
			var prevTex = tex.path;
			var e = new hide.Element('<li style="position:relative">
				<input type="checkbox" field="enable"/>
				<input type="texturepath" style="width:160px" field="path"/>
				<select field="kind" style="width:70px">
					<option value="albedo">Albedo
					<option value="height">Height
					<option value="normal">Normal
					<option value="splatmap">SplatMap
					<option value="albedoProps">Albedo + Props
					<option value="delete">-- Delete --
				</select>
				<a href="#" class="up">🡅</a>
				<a href="#" class="down">🡇</a>
			</li>
			');
			e.find(".up").click(function(_) {
				var index = textures.indexOf(tex);
				if( index <= 0 ) return;
				textures.remove(tex);
				textures.insert(index-1, tex);
				ectx.rebuildProperties();
				updateInstance();
			});
			e.find(".down").click(function(_) {
				var index = textures.indexOf(tex);
				textures.remove(tex);
				textures.insert(index+1, tex);
				ectx.rebuildProperties();
				updateInstance();
			});
			e.appendTo(list);
			ectx.properties.build(e, tex, (pname) -> {
				if( pname == "kind" ) {
					if( ""+tex.kind == "albedoProps" ) {
						tex.kind = Albedo;
						if( tex.props == null ) {
							tex.props = {
								color : 0xFFFFFF,
								scale : 1,
							};
							ectx.rebuildProperties();
						}
					} else if( tex.props != null ) {
						tex.props = null;
						ectx.rebuildProperties();
					}
				}
				if( tex.path != prevTex ) {
					tex.enable = true; // enable on change texture !
					prevTex = tex.path;
				}
				if( ""+tex.kind == "delete" ) {
					textures.remove(tex);
					ectx.rebuildProperties();
				}
				updateInstance(pname);
			});
			if( tex.props != null ) {
				var e = new hide.Element('<li style="position:relative">
					Scale <input type="range" min="0" max="10" field="scale"/>
					<input type="color" field="color"/>
 				</li>');
				e.appendTo(list);
				ectx.properties.build(e, tex.props, (pname) -> updateAlbedoProps());
			}
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(list);
		add.find("a").click(function(_) {
			textures.push({ path : null, kind : Albedo, enable: true });
			ectx.rebuildProperties();
		});
	}

	override public function getDisplayFilters() : Array<String> {
		var filters = ["highQuality"];
		if (view != null) {
			for (tex in textures) {
				if (!filters.contains(Std.string(tex.kind)))
					filters.push(Std.string(tex.kind));
			}
		}
		return filters;
	}
	#end

	static var _ = Prefab.register("heightmap", HeightMap);

}


class HeightGrid extends h3d.prim.Primitive {

	/**
		The number of cells in width
	**/
	public var width (default, null) : Int;

	/**
		The number of cells in height
	**/
	public var height (default, null)  : Int;

	/**
		The width of a cell
	**/
	public var cellWidth (default, null) : Float;

	/**
		The height of a cell
	**/
	public var cellHeight (default, null)  : Float;

	/**
	 *  Minimal Z value, used for reporting bounds.
	 **/
	public var zMin = 0.;

	/**
	 *  Maximal Z value, used for reporting bounds.
	 **/
	public var zMax = 0.;

	public var xOffset = 0.;
	public var yOffset = 0.;

	var hasNormals : Bool;
	var hasUVs : Bool;

	public function new( width : Int, height : Int, cellWidth = 1., cellHeight = 1., xOffset = 0., yOffset = 0. ) {
		this.width = width;
		this.height = height;
		this.cellWidth = cellWidth;
		this.cellHeight = cellHeight;
		this.xOffset = xOffset;
		this.yOffset = yOffset;
	}

	public function addNormals() {
		hasNormals = true;
	}

	public function addUVs() {
		hasUVs = true;
	}

	override function getBounds():h3d.col.Bounds {
		return h3d.col.Bounds.fromValues(xOffset,yOffset,zMin,width*cellWidth+xOffset,height*cellHeight+yOffset,zMax-zMin);
	}

	override function alloc(engine:h3d.Engine) {
		dispose();
		var format = if( hasNormals && hasUVs )
			hxd.BufferFormat.POS3D_NORMAL_UV;
		else if( hasNormals )
			hxd.BufferFormat.POS3D_NORMAL
		else if( hasUVs )
			hxd.BufferFormat.POS3D_UV
		else
			hxd.BufferFormat.POS3D;
		var buf = new hxd.FloatBuffer((width + 1) * (height +  1) * format.stride);
		var p = 0;
		for( y in 0...height + 1 )
			for( x in 0...width + 1 ) {
				buf[p++] = x * cellWidth + xOffset;
				buf[p++] = y * cellHeight + yOffset;
				buf[p++] = 0;
				if( hasNormals ) {
					buf[p++] = 0;
					buf[p++] = 0;
					buf[p++] = 1;
				}
				if( hasUVs ) {
					buf[p++] = x / width;
					buf[p++] = y / height;
				}
			}
		buffer = h3d.Buffer.ofFloats(buf, format);
		indexes = new h3d.Indexes(width * height * 6, true);
		var b = haxe.io.Bytes.alloc(indexes.count * 4);
		var p = 0;
		for( y in 0...height )
			for( x in 0...width ) {
				var s = x + y * (width + 1);
				b.setInt32(p++ << 2, s);
				b.setInt32(p++ << 2, s + 1);
				b.setInt32(p++ << 2, s + width + 1);
				b.setInt32(p++ << 2, s + 1);
				b.setInt32(p++ << 2, s + width + 2);
				b.setInt32(p++ << 2, s + width + 1);
			}
		indexes.uploadBytes(b,0,indexes.count);
	}

}
