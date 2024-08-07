package hrt.prefab.l3d;
import h3d.mat.PbrMaterial;
import hxd.fmt.hmd.Data;

typedef MaterialData = {
	var indexStart : Int;
	var indexCount : Int;
	var geomId : Int;
	var lodIndexStart : Array<Int>;
	var lodIndexCount : Array<Int>;
	var texId : Int;
	var uvX : Float;
	var uvY : Float;
	var uvSX : Float;
	var uvSY : Float;
}

typedef MaterialMesh = {
	mat : MaterialData,
	mesh : h3d.scene.Mesh,
}
typedef SubMeshes = {
	meshes : Array<MaterialMesh>,
	name : String,
}

typedef CreateMeshBatchFunc = ( library : hrt.prefab.l3d.ModelLibrary, parent : h3d.scene.Object, isStatic : Bool, ?bounds : h3d.col.Bounds, ?props : h3d.mat.PbrMaterial.PbrProps, ?material : h3d.mat.Material) -> h3d.scene.MeshBatch;

class MeshEmitter {

	var libraryInstance : ModelLibraryInstance;
	var materials : Array<MaterialData>;
	var batches : Array<Int>;
	var mesh : h3d.scene.Mesh;

	function new(libraryInstance : ModelLibraryInstance, batches : Array<Int>, materials : Array<MaterialData>, mesh : h3d.scene.Mesh ) {
		this.libraryInstance = libraryInstance;
		this.batches = batches;
		this.materials = materials;
		this.mesh = mesh;
	}

	public function emit( absPos : h3d.Matrix, emitCountTip : Int = -1 ) {
		for ( i => mat in materials ) {
			var batch = @:privateAccess libraryInstance.getBatch(batches[i]);
			libraryInstance.library.emit({ mat : mat, mesh : mesh }, batch, absPos, emitCountTip, batch.meshBatchFlags);
		}
	}

}

class ModelLibraryInstance {
	public var library : ModelLibrary;
	var batchCache: Array<h3d.scene.MeshBatch>;
	var batchLookup : Map<String, Int>;

	var materialCache : Map<h3d.mat.Material, Int>;

	function new(library : ModelLibrary) {
		this.library = library;
		batchCache = [];
		batchLookup = new Map<String, Int>();
	}

	function getBatch( id : Int ) {
		return batchCache[id];
	}

	public function applyShader( s : hxsl.Shader ) {
		for ( batch in batchCache ) {
			if ( batch.material.mainPass.getShader( Type.getClass(s) ) != null )
				batch.material.mainPass.removeShader(s);
			batch.material.mainPass.addShader(s);
		}
	}

	public function createMeshEmitter( mesh : h3d.scene.Mesh, parent : h3d.scene.Object, ?createMeshBatch : CreateMeshBatchFunc, appendToKey : String = "" ) : MeshEmitter {
		var batches : Array<Int> = [];
		var materials = [];

		for ( material in mesh.getMaterials(false) ) {
			var materialClone = cast(material.clone(), h3d.mat.Material);

			var props = h3d.mat.MaterialSetup.current.loadMaterialProps(material);
			var prefab = null;
			if ( props != null ) {
				var ref = (props:Dynamic).__ref;
				if ( ref != null ) {
					prefab = hxd.res.Loader.currentInstance.load(ref).toPrefab();
					hxd.fmt.hmd.Library.setupMaterialLibrary(path -> hxd.res.Loader.currentInstance.load(path).toTexture(),
					materialClone, prefab, (props:Dynamic).name);
				}
			}

			var shaderKey = "";
			var props = (material.props : PbrProps);
			var libMat = prefab != null ? prefab.load().getOpt(hrt.prefab.Material, (props:Dynamic).name) : null;
			if ( libMat != null )
				for ( c in libMat.children )
					shaderKey = haxe.Json.stringify(@:privateAccess c.serialize());
			var key = haxe.Json.stringify(props) + shaderKey + appendToKey;

			var batchID = batchLookup.get(key);
			if ( batchID == null ) {
				batchID = batchCache.length;
				var batch = createMeshBatch == null ? library.createMeshBatch(parent, false, null, props, materialClone) : createMeshBatch(library, parent, false, null, props, materialClone);
				if ( batch == null )
					continue;
				batchLookup.set(key, batchID);
				batchCache.push(batch);
			}

			batches.push( batchID );
			materials.push( library.getBakedMat(material, cast(mesh.primitive, h3d.prim.HMDModel), mesh.name) );
		}

		return @:privateAccess new MeshEmitter(this, batches, materials, mesh);
	}

	public function remove() {
		for ( b in batchCache )
			b.remove();
		batchLookup.clear();
		batchCache.resize(0);
	}
}

class ModelLibShader extends hxsl.Shader {
	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@param @perInstance var uvTransform : Vec4;
		@param @perInstance var libraryParams : Vec4;

		@const var singleTexture : Bool;
		@const var hasNormal : Bool;
		@const var hasPbr : Bool;

		@param var texture : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var specular : Sampler2D;

		@param var textures : Sampler2DArray;
		@param var normalMaps : Sampler2DArray;
		@param var speculars : Sampler2DArray;

		@param var mipStart : Float;
		@param var mipEnd : Float;
		@param var mipPower : Float;
		@param var mipNumber : Float;

		@input var input2 : {
			var tangent : Vec3;
			var uv : Vec2;
		};

		var calculatedUV : Vec2;
		var transformedTangent : Vec4;

		var metalness : Float;
		var roughness : Float;
		var occlusion : Float;

		var mipLevel : Float;

		function unpackPBR(v : Vec4) : Vec4 {
			metalness = v.r;
			roughness = 1 - v.g * v.g;
			occlusion = v.b;
			// no emissive for now
		}

		function __init__vertex() {
			previousTransformedPosition = transformedPosition;
			if( hasNormal )
				transformedTangent = vec4(input2.tangent * global.modelView.mat3(),input2.tangent.dot(input2.tangent) > 0.5 ? 1. : -1.);
			mipLevel = pow(saturate((projectedPosition.z - mipStart) / (mipEnd - mipStart)), mipPower) * mipNumber;
		}

		function __init__fragment() {
			calculatedUV = clamp(input2.uv.fract(), libraryParams.y, 1.0 - libraryParams.y);
			calculatedUV = calculatedUV * uvTransform.zw + uvTransform.xy;
			pixelColor = singleTexture ? texture.getLod(calculatedUV, mipLevel) : textures.getLod(vec3(calculatedUV, libraryParams.x), mipLevel);
			if( hasNormal ) {
				var n = transformedNormal;
				var nf = unpackNormal(singleTexture ? normalMap.getLod(calculatedUV, mipLevel) : normalMaps.getLod(vec3(calculatedUV, libraryParams.x), mipLevel));
				var tanX = transformedTangent.xyz.normalize();
				var tanY = n.cross(tanX) * -transformedTangent.w;
				transformedNormal = (nf.x * tanX + nf.y * tanY + nf.z * n).normalize();
			}
			if( hasPbr ) {
				var v = singleTexture ? specular.getLod(calculatedUV, mipLevel) : speculars.getLod(vec3(calculatedUV, libraryParams.x), mipLevel);
				unpackPBR(v);
			}
		}

	}
}

class ModelLibraryCache {
	public function new() {};
	public var wasMade = false;
	public var hmdPrim : h3d.prim.HMDModel;
	public var shader : ModelLibShader;
	public var geomBounds : Array<h3d.col.Bounds>;
}

class ModelLibrary extends Prefab {

	@:s var bakedMaterials : haxe.DynamicAccess<MaterialData>;
	@:s var texturesCount : Int;

	@:s var ignoredMaterials : Array<{name:String}> = [];
	@:s var ignoredPrefabs : Array<{name:String}> = [];
	@:s var ignoredObjectNames : Array<{name:String}> = [];
	@:s var preserveObjectNames : Array<{name:String}> = [];

	@:s var meshConvertRule : String = "";

	@:s var mipEnd : Float;
	@:s var mipStart : Float;
	@:s var mipPower : Float;
	@:s var mipLevels : Int = 1;
	@:s var compress : Bool = true;

	var cache : ModelLibraryCache;
	var btSize = 4096;
	var errors = [];
    final reg = ~/[0-9]+/g;

	var killAlpha = new h3d.shader.KillAlpha(0.5);

	public function new(prefab, shared) {
		super(prefab, shared);
		cache = new ModelLibraryCache();
	}

	#if !editor
	override function clone(?parent:Prefab = null, ?sh: ContextShared = null, withChildren : Bool = true) : Prefab {
		var clone : ModelLibrary = cast super.clone(parent, sh, withChildren);
		clone.cache = cache;
		return clone;
	}
	#end

	public function createLibraryInstance() : ModelLibraryInstance {
		return @:privateAccess new ModelLibraryInstance(this);
	}

	function update( text : String ) {
		#if editor
		hide.Ide.inst.setProgress(text);
		#else
		trace(text);
		#end
	}

	function loadTexture(sourcePath : String, texPath : String) {
		#if editor
		return shared.scene.loadTexture(sourcePath, texPath);
		#else
		return hxd.res.Loader.currentInstance.load(texPath).toTexture();
		#end
	}

	function pushError(err : String) {
		#if editor
		hide.Ide.inst.error(err);
		#else
		trace(err);
		#end
	}

	function isTextureNew( name : String, time : Float ) : Bool {
		var filePath = getSystemPath(name);
		if ( !sys.FileSystem.exists(filePath) )
			return false;
		return sys.FileSystem.stat(filePath).mtime.getTime() > time ;
	}

	function isModelNew( model : hrt.prefab.Model, time : Float ) : Bool {
		var source = getSystemPath(model.source);
		if ( !sys.FileSystem.exists(source) )
			return false;

		if ( sys.FileSystem.stat(source).mtime.getTime() > time )
			return true;

		var shared = new hrt.prefab.ContextShared();
		var lib = null;
		for( m in shared.loadModel(model.source).getMeshes() ) {
			var m = Std.downcast(m.primitive, h3d.prim.HMDModel);
			if( m != null ) {
				lib = @:privateAccess m.lib;
				break;
			}
		}

		var sourceDir = source.substring( 0, source.lastIndexOf("/") );
		var matPropsPath = sourceDir + "/materials.props";
		if ( sys.FileSystem.exists(matPropsPath) )
			if ( sys.FileSystem.stat(matPropsPath).mtime.getTime() > time )
				return false;

		for ( m in lib.header.materials ) {
			var mat = h3d.mat.MaterialSetup.current.createMaterial();
			mat.name = m.name;
			mat.model = lib.resource;
			var props = h3d.mat.MaterialSetup.current.loadMaterialProps(mat);
			if( props == null )
				continue;

			if( (props:Dynamic).__ref != null ) {
				try {
					var lib = hxd.res.Loader.currentInstance.load((props:Dynamic).__ref).toPrefab().load();

					var libPath = getSystemPath(lib.shared.prefabSource);
					if ( sys.FileSystem.stat(libPath).mtime.getTime() > time )
						return false;

					var m = lib.getOpt(hrt.prefab.Material, (props:Dynamic).name);
					if( m.diffuseMap != null )
						if ( isTextureNew(m.diffuseMap, time) )
							return true;
					if( m.specularMap != null )
						if ( isTextureNew(m.specularMap, time) )
							return true;
					if( m.normalMap != null )
						if ( isTextureNew(m.normalMap, time) )
							return true;
					continue;
				} catch( e : Dynamic ) { continue; }
			}

			if( m.diffuseTexture != null )
				if ( isTextureNew(m.diffuseTexture, time) )
					return true;
			if( m.specularTexture != null )
				if ( isTextureNew(m.specularTexture, time) )
					return true;
			if( m.normalMap != null )
				if ( isTextureNew(m.normalMap, time) )
					return true;
		}

		return false;
	}

	static inline function getSystemPath( path : String ) : String {
		#if editor
		return hide.Ide.inst.getPath(path);
		#else
		return "res/" + path;
		#end
	}

	public function isUpToDate( ?paths : Array<String> ) : Bool {
		var source = shared.prefabSource;
		if ( source == null )
			return false;

		var filePath = getSystemPath(source);
		if ( !sys.FileSystem.exists(filePath) )
			return false;

		var fileStat = sys.FileSystem.stat(filePath);
		var time = fileStat.mtime.getTime();

		var models = findAll(hrt.prefab.Model);

		if ( paths != null ) {
			if ( paths.length != models.length )
				return false;

			for ( path in paths ) {
				var found = false;
				for ( m in models ) {
					if ( m.source == path ) {
						found = true;
						break;
					}
				}
				if ( !found )
					return false;
			}
		}

		var fs = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		var dirPath = shared.currentPath.split(".prefab")[0];
		var config = haxe.Json.stringify(@:privateAccess fs.convert.getConvertRule(dirPath+".fbx"));
		if ( config != meshConvertRule )
			return false;

		for ( m in models)
			if ( isModelNew(m, time) )
				return false;

		return true;
	}

	public function rebuildData() {

		bakedMaterials = {};

		var hmd = new Data();
		hmd.version = Data.CURRENT_VERSION;
		hmd.geometries = [];
		hmd.materials = [];
		hmd.models = [];
		hmd.animations = [];
		hmd.shapes = [];
		var models = new Map();
		var dataOut = new haxe.io.BytesOutput();

		var textures : Array<h3d.mat.BigTexture> = [];
		var normalMaps : Array<h3d.mat.BigTexture> = [];
		var specMaps : Array<h3d.mat.BigTexture> = [];
		var tmap = new Map();

		inline function allocDefault(name,color,alpha=1) {
			var tex = new h3d.mat.Texture(16,16);
			tex.setName(name);
			tex.clear(color,alpha);
			var bytes = tex.capturePixels().toDDS();
			return { tex : tex, bytes : bytes };
		}

		var whiteDefault = allocDefault("white",0xFFFFFF);
		var normalDefault = allocDefault("normal",0x8080FF);
		var specDefault = allocDefault("spec",0x0000FF);

		var matName = "???";

		inline function error( text : String ) {
			errors.push(text);
		}

		function packTexture( sourcePath, texPath, normalMap, specMap ) {
			inline function getPath(p : String) {
				#if editor
				return hide.Ide.inst.getPath(p);
				#else
				return "res/" + p;
				#end
			}
			var t = null;
			if ( texPath == null )
				return null;
			var tmp = loadTexture(sourcePath, texPath);

			var ntex = normalMap == null ? null : loadTexture(sourcePath, normalMap);
			var stex = specMap == null ? null : loadTexture(sourcePath, specMap);
			var key = texPath+"/"+(ntex==null?"nonorm":ntex.name)+(stex==null?"nospec":stex.name);
			t = tmap.get(key);
			if( t != null )
				return t;
			update("Packing "+key);
			var realTex = hxd.res.Any.fromBytes(tmp.name, tmp == whiteDefault.tex ? whiteDefault.bytes : sys.io.File.getBytes(getPath(tmp.name))).toImage();
			for ( mipLevel in 0...mipLevels ) {
				var texture = realTex.toTexture();
				var size = hxd.Math.imax(texture.width >> mipLevel, 1 << (mipLevels - mipLevel - 1));
				var resizedTex = new h3d.mat.Texture(size, size, [Target], texture.format);
				h3d.pass.Copy.run(texture, resizedTex);
				var texBytes = resizedTex.capturePixels().toDDS();
				resizedTex.dispose();
				var mipLevelImage = hxd.res.Any.fromBytes(tmp.name+"_"+mipLevel, texBytes).toImage();

				var pos = null, posTex = null;
				for( i in 0...textures.length ) {
					if ( (i % mipLevels) != mipLevel )
						continue;
					var b = textures[i];
					pos = b.add(mipLevelImage);
					if( pos != null ) {
						posTex = b;
						break;
					}
				}
				if( pos == null ) {
					var b = new h3d.mat.BigTexture(textures.length, btSize >> mipLevel, 0);
					textures.push(b);
					pos = b.add(mipLevelImage);
					posTex = b;
				}
				if ( mipLevel == 0) {
					t = {
						pos : pos,
						tex : posTex,
					};
				}

				function packSub(textures:Array<h3d.mat.BigTexture>, tex : h3d.mat.Texture, isSpec ) {
					var t = textures[posTex.id];
					if( t == null ) {
						t = new h3d.mat.BigTexture(textures.length, btSize >> mipLevel, isSpec ? 0xFFFFFF : 0xFF8080FF);
						textures[posTex.id] = t;
					}
					var inf = realTex.getInfo();
					if( tex == null ) {
						var path = isSpec ? specMap : normalMap;
						if( path != null )
							error('Missing texture $sourcePath($path)');
						else
							error('$sourcePath material ${matName} is missing ${isSpec?"specular":"normal"} texture set');

						if( isSpec )
							tex = specDefault.tex;
						else
							tex = normalDefault.tex;
					}
					var texBytes = if( tex == normalDefault.tex ) normalDefault.bytes else if( tex == specDefault.tex ) specDefault.bytes else sys.io.File.getBytes(getPath(tex.name));
					var realTex = hxd.res.Any.fromBytes(tex.name, texBytes).toImage();
					var inf2 = realTex.getInfo();
					if( inf2.width != inf.width || inf2.height != inf.height ) {
						if( tex != normalDefault.tex && tex != specDefault.tex )
							error([
								(isSpec?"Specular texture ":"Normal map ")+" has size not matching the albedo",
								"  Texture: "+tex.name+'(${inf2.width}x${inf2.height})',
								"  Albedo: "+texPath+'(${inf.width}x${inf.height})',
								"  Model: "+sourcePath+"@"+matName,
							].join("\n"));
					}
					var texture = realTex.toTexture();
					var size = hxd.Math.imax(inf.width >> mipLevel, 1 << (mipLevels - mipLevel - 1));
					var resizedTex = new h3d.mat.Texture(size, size, [Target], texture.format);
					h3d.pass.Copy.run(texture, resizedTex);
					var texBytes = resizedTex.capturePixels().toDDS();
					resizedTex.dispose();
					var submiplevelImage = hxd.res.Any.fromBytes(tmp.name+"_"+mipLevel, texBytes).toImage();
					t.add(submiplevelImage);
				}

				packSub(normalMaps, ntex, false);
				packSub(specMaps, stex, true);

			}
			tmap.set(key, t);
			return t;
		}

		var indexStarts = [], currentIndex = 0, currentVertex = 0;
		var dataToStore = [];

		var geomAll = new Geometry();
		var hasTangents = false;
		geomAll.bounds = new h3d.col.Bounds();
		geomAll.bounds.addPos(0,0,0);
		geomAll.indexCounts = [];
		geomAll.vertexFormat = hxd.BufferFormat.POS3D_NORMAL;

		hmd.geometries.push(geomAll);
		indexStarts.push(null);

		var modelRoot = new Model();
		modelRoot.name = "ROOT";
		modelRoot.geometry = 0;
		modelRoot.parent = -1;
		modelRoot.position = new Position();
		modelRoot.position.x = 0;
		modelRoot.position.y = 0;
		modelRoot.position.z = 0;
		modelRoot.position.sx = 1;
		modelRoot.position.sy = 1;
		modelRoot.position.sz = 1;
		modelRoot.position.qx = 0;
		modelRoot.position.qy = 0;
		modelRoot.position.qz = 0;
		hmd.models.push(modelRoot);

		for( m in findAll(hrt.prefab.Model, true) ) {
			if( models.exists(m.source) )
				continue;
			if( m.findParent(hrt.prefab.fx.FX) != null )
				continue;
			var ignoreModel = false;
			if ( m.animation != null )
				continue;
			for ( shader in ignoredPrefabs) {
				var cl : Class<hrt.prefab.Prefab> = cast Type.resolveClass(shader.name);
				if( cl != null ) {
					for ( c in m.children ) {
						if ( Std.isOfType(c, cl) ) {
							ignoreModel = true;
							break;
						}
					}
					if ( m.parent != null ) {
						for ( c in m.parent.children ) {
							if ( Std.isOfType(c, cl) ) {
								ignoreModel = true;
								break;
							}
						}
					}
				}
			}
			if ( ignoreModel )
				continue;
			var sourcePath = m.source;
			models.set(m.source, true);
			var lib = null;
			for( m in shared.loadModel(m.source).getMeshes() ) {
				var m = Std.downcast(m.primitive, h3d.prim.HMDModel);
				if( m != null ) {
					lib = @:privateAccess m.lib;
					break;
				}
			}
			if( lib == null ) continue;

			function addMaterial( mid : Int, modelName : String ) {
				var m = lib.header.materials[mid];

				var m2 = new Material();
				m2.name = m.name;
				m2.props = m.props;
				m2.blendMode = m.blendMode;
				matName = m.name;

				var heapsMat = @:privateAccess lib.makeMaterial(lib.header.models[mid], mid, function(path:String) { return loadTexture(sourcePath, path);});
				var diffuseTexture = m.diffuseTexture;
				var tshader = heapsMat.mainPass.getShader(h3d.shader.Texture);
				if ( tshader != null )
					diffuseTexture = tshader.texture.name;
				var normalMap = m.normalMap;
				var nmshader = heapsMat.mainPass.getShader(h3d.shader.NormalMap);
				if ( nmshader != null )
					normalMap = nmshader.texture.name;
				var specularTexture = m.specularTexture;
				var pshader = heapsMat.mainPass.getShader(h3d.shader.pbr.PropsTexture);
				if ( pshader != null )
					specularTexture = pshader.texture.name;
				else {
					var pshader = heapsMat.mainPass.getShader(h3d.shader.SpecularTexture);
					if ( pshader != null )
						specularTexture = pshader.texture.name;
				}

				var pos = packTexture(sourcePath, diffuseTexture, normalMap, specularTexture);
				if ( pos == null )
					return null;
				var matName = m.name;
				matName = reg.replace(matName, '');
				var key = lib.resource.entry.path + (modelName != "root" ? "_" + modelName : "") + "_" + matName;
				var bk = bakedMaterials.get(key);
				if ( bk != null )
					return bk;
				bk = {
					indexStart : 0,
					indexCount : 0,
					geomId : 0,
					lodIndexStart : [],
					lodIndexCount : [],
					texId : hxd.Math.floor(pos.tex.id / mipLevels),
					uvX : pos.pos.du,
					uvY : pos.pos.dv,
					uvSX : pos.pos.su,
					uvSY : pos.pos.sv
				};
				bakedMaterials.set(key, bk);

				hmd.materials.push(m2);
				return bk;
			}

			var offsetGeom = hmd.geometries.length;
			var offsetModels = hmd.models.length;
			var libData = lib.getData();

			for( g in lib.header.geometries ) {

				if( !hasTangents && g.vertexFormat.hasInput("tangent") ) {
					hasTangents = true;
					geomAll.vertexFormat = geomAll.vertexFormat.append("tangent",DVec3);
				}

				var g2 = new Geometry();
				g2.props = g.props;
				g2.vertexCount = 0;
				g2.vertexFormat = g.vertexFormat;
				g2.indexCounts = [];
				g2.bounds = g.bounds;
				hmd.geometries.push(g2);

				dataToStore.push({ g : g2, origin : g, lib : lib, data : libData, offset : currentVertex });
				currentVertex += g.vertexCount;

				var arr = [];
				for( i in g.indexCounts ) {
					arr.push(currentIndex);
					currentIndex += i;
					geomAll.indexCounts.push(i);
				}
				indexStarts.push(arr);
			}

			var root = true;
			for( m in lib.header.models ) {
				var lodInfos = lib.getLODInfos(m);
				if ( lodInfos.lodLevel > 0 )
					continue;

				var ignoreModel = false;
				var m2 = new Model();
				m2.name = m.name;
				m2.props = m.props;
				m2.parent = m.parent < 0 ? 0 : m.parent + offsetModels;
				m2.follow = m.follow;
				m2.position = m.position;
				m2.geometry = m.geometry < 0 ? -1 : m.geometry + offsetGeom;
				if( m.materials != null ) {
					m2.materials = [];
					for( index => mid in m.materials ) {
						for ( ignoredMat in ignoredMaterials ) {
							if ( lib.header.materials[mid].name.indexOf(ignoredMat.name) == 0 ) {
								ignoreModel = true;
								break;
							}
						}
						if ( ignoreModel )
							break;
						var mat = addMaterial(mid, root ? "root" : m.name);
						if ( mat != null ) {
							mat.geomId = m2.geometry;
							mat.indexCount = lib.header.geometries[m.geometry].indexCounts[index];
							mat.indexStart = indexStarts[m2.geometry][index];

							if ( lodInfos.lodLevel == 0 ) {
								var lods = lib.findLODs(lodInfos.modelName);
								mat.lodIndexCount = [];
								mat.lodIndexStart = [];
								mat.lodIndexCount.resize(lods.length);
								mat.lodIndexStart.resize(lods.length);
								for ( i => lod in lods ) {
									mat.lodIndexCount[i] = lod.indexCounts[index];
									var geometry = lib.header.geometries.indexOf(lod);
									if ( geometry < 0 )
										throw "Geometry not found";
									mat.lodIndexStart[i] = indexStarts[geometry + offsetGeom][index];
								}
							}

							m2.materials.push(hmd.materials.length - 1);
						}
					}
				}
				if( m.skin != null )
					error("Not supported: "+sourcePath+"("+m.name+") has skin");
				hmd.models.push(m2);
				root = false;
			}
		}

		modelRoot.materials = [for( i in 0...hmd.materials.length ) i];
		geomAll.vertexFormat = geomAll.vertexFormat.append("uv",DVec2);

		var highPrecFormat = geomAll.vertexFormat;
		var fs = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		if ( fs != null ) {
			var dirPath = shared.currentPath.split(".prefab")[0];
			var config = @:privateAccess fs.convert.getConvertRule(dirPath+".fbx");
			meshConvertRule = haxe.Json.stringify(config);
			var lowp = Reflect.field(config.cmd.params, "lowp");
			if ( lowp != null ) {
				var lowpInputs = [];
				for ( i in geomAll.vertexFormat.getInputs() ) {
					var precStr = Reflect.field(lowp, hxd.fmt.fbx.HMDOut.remapPrecision(i.name));
					var prec = hxd.BufferFormat.Precision.F32;
					if ( precStr != null ) {
						prec = switch ( precStr ) {
						case "f32": F32;
						case "f16": F16;
						case "u8": U8;
						case "s8": S8;
						default: throw "unsupported precision";
						}
					}
					lowpInputs.push(new hxd.BufferFormat.BufferInput(i.name, i.type, prec));
				}
				geomAll.vertexFormat = hxd.BufferFormat.make(lowpInputs);
			}
		}

		geomAll.vertexCount = currentVertex;
		geomAll.vertexPosition = dataOut.length;
		if( geomAll.vertexFormat.stride < 3 ) {
			pushError("No model found in data");
			return;
		}

		for( inf in dataToStore ) {
			var g = inf.g;
			g.vertexPosition = dataOut.length;
			var buf = inf.lib.getBuffers(inf.origin, highPrecFormat, [for( _ in highPrecFormat.getInputs() ) new h3d.Vector4(0,0,0,0)]);
			if ( !geomAll.vertexFormat.hasLowPrecision ) {
				for( i in 0...geomAll.vertexFormat.stride * inf.origin.vertexCount )
					hxd.fmt.fbx.HMDOut.writeFloat(dataOut, buf.vertexes[i]);
			} else {
				var mapping = [];
				for ( i in geomAll.vertexFormat.getInputs() )
					mapping.push({size : i.type.getSize(), prec : i.precision});
				for ( i in 0...inf.origin.vertexCount ) {
					var  p = 0;
					for ( m in mapping ) {
						for ( _ in 0...m.size ) {
							hxd.fmt.fbx.HMDOut.writePrec(dataOut, buf.vertexes[i * geomAll.vertexFormat.stride + p], m.prec);
							p++;
						}
						hxd.fmt.fbx.HMDOut.flushPrec(dataOut, m.prec, m.size);
					}
				}
			}
		}

		geomAll.indexPosition = dataOut.length;
		for( inf in dataToStore ) {
			var g = inf.g;
			g.indexPosition = dataOut.length;
			var dataPos = inf.origin.indexPosition;
			var read16 = inf.origin.vertexCount <= 0x10000;
			var write16 = geomAll.vertexCount <= 0x10000;
			for( i in 0...inf.origin.indexCount ) {
				var idx = read16 ? inf.data.getUInt16(dataPos + (i<<1)) : inf.data.getInt32(dataPos + (i<<2));
				if( write16 )
					dataOut.writeUInt16(idx + inf.offset);
				else
					dataOut.writeInt32(idx + inf.offset);
			}
		}

		hmd.data = dataOut.getBytes();
		var out = new haxe.io.BytesOutput();
		var w = new hxd.fmt.hmd.Writer(out);
		w.write(hmd);
		var bytes = out.getBytes();
		shared.savePrefabDat("model","hmd",name,bytes);

		texturesCount = textures.length;
		inline function makeTex(textures:Array<h3d.mat.BigTexture>, name : String ) {
			var all = [];
			for( i in 0...textures.length ) {
				var t = textures[i];
				update("Making "+name+"@"+(t.id+1)+"/"+textures.length);
				@:privateAccess t.onPixelsReady = function(pix) {
					all.push(pix.clone());
					haxe.Timer.delay(t.dispose, 0);
				}
				t.done();
			}
			shared.savePrefabDat(name,"dds",this.name, hxd.Pixels.toDDSLayers(all));
		}
		makeTex(textures,"texture");
		makeTex(normalMaps,"normal");
		makeTex(specMaps,"specular");
	}

	public function saveLibrary( ?filePath : String ) {
		var path = ( filePath != null ) ? filePath : shared.prefabSource;
		if ( path == null )
			throw "There is no destination path for saving the model library";

		var root = new hrt.prefab.Prefab(null, null);
		parent = root;
		sys.io.File.saveContent(getSystemPath(path), haxe.Json.stringify(@:privateAccess root.serialize(), "\t"));
	}

	public static function createLibrary( dir : String, name : String, paths : Array<String> ) {
		var systemDir = getSystemPath(dir);
		if ( !sys.FileSystem.exists(systemDir) )
			sys.FileSystem.createDirectory(systemDir);
		var modelLib = new hrt.prefab.l3d.ModelLibrary(null, null);
		modelLib.name = "Library";
		var pathes = [];
		for ( path in paths ) {
			var model = new hrt.prefab.Model(modelLib, null);
			var p = new haxe.io.Path(path);
			model.name = p.file;
			model.source = path;
		}
		modelLib.saveLibrary(dir + name);
	}

	#if !editor
	override function make(?sh:hrt.prefab.Prefab.ContextMake) : hrt.prefab.Prefab {
		// don't load/build children
		if (cache.wasMade)
			return this;

		if ( cache.hmdPrim == null ) {
			try {
				cache.hmdPrim = Std.downcast(shared.loadModel(shared.getPrefabDatPath("model","hmd",this.name)).toMesh().primitive, h3d.prim.HMDModel);
			} catch ( e : Dynamic ) {
				return this;
			}
		}
		cache.wasMade = true;
		if ( cache.geomBounds == null )
			cache.geomBounds = [for( g in @:privateAccess cache.hmdPrim.lib.header.geometries ) g.bounds];
		@:privateAccess cache.hmdPrim.curMaterial = -1;
		if ( cache.shader == null ) {
			cache.shader = cast(h3d.mat.MaterialSetup.current, h3d.mat.PbrMaterialSetup).createModelLibShader();
			cache.shader.mipStart = mipStart;
			cache.shader.mipEnd = mipEnd;
			cache.shader.mipPower = mipPower;
			cache.shader.mipNumber = mipLevels;
			var tex = shared.loadTexture(shared.getPrefabDatPath("texture","dds",this.name));
			var tnormal = try shared.loadTexture(shared.getPrefabDatPath("normal","dds",this.name)) catch( e : hxd.res.NotFound ) null;
			var tspec = try shared.loadTexture(shared.getPrefabDatPath("specular","dds",this.name)) catch( e : hxd.res.NotFound ) null;
			tex.wrap = Repeat;
			tnormal.wrap = Repeat;
			tspec.wrap = Repeat;
			if( texturesCount == 1 || !Std.isOfType(tex, h3d.mat.TextureArray) ) {
				cache.shader.singleTexture = true;
				cache.shader.texture = tex;
				cache.shader.normalMap = tnormal;
				cache.shader.specular = tspec;
			} else {
				cache.shader.textures = cast(tex,h3d.mat.TextureArray);
				cache.shader.normalMaps = cast(tnormal,h3d.mat.TextureArray);
				cache.shader.speculars = cast(tspec,h3d.mat.TextureArray);
			}
			cache.shader.hasNormal = tnormal != null;
			cache.shader.hasPbr = tspec != null;
		}
		return this;
	}
	#end

	public function getPrim() {
		return cache.hmdPrim;
	}

	public function createMeshBatch(parent : h3d.scene.Object, isStatic : Bool, ?bounds : h3d.col.Bounds, ?props : h3d.mat.PbrMaterial.PbrProps, ?material : h3d.mat.Material) {
		var batch = new h3d.scene.MeshBatch(cache.hmdPrim, h3d.mat.Material.create(), parent);
		setupMeshBatch(batch, isStatic, bounds, props, material);
		return batch;
	}


	var forbiddenShaderTypes : Array<Class<hxsl.Shader>> = [h3d.shader.pbr.PropsTexture, h3d.shader.Texture, h3d.shader.NormalMap];
	function isForbiddenShader(s) : Bool {
		for ( type in forbiddenShaderTypes )
			if ( Std.isOfType(s, type ) )
				return true;
		return false;
	}

	public function setupMeshBatch(batch : h3d.scene.MeshBatch, isStatic : Bool, ?bounds : h3d.col.Bounds, ?props : h3d.mat.PbrMaterial.PbrProps, ?material : h3d.mat.Material ) {

		if ( material != null ) {
			for ( s in material.mainPass.getShaders())
				if ( !isForbiddenShader(s) && batch.material.mainPass.getShader(Type.getClass(s)) == null )
					batch.material.mainPass.addShader(s.clone());
			for ( s in @:privateAccess material.mainPass.selfShaders )
				if ( !isForbiddenShader(s) && batch.material.mainPass.getShader(Type.getClass(s)) == null )
					@:privateAccess batch.material.mainPass.addSelfShader(s.clone());
		}

		if ( isStatic ) {
			batch.material.staticShadows = true;
			batch.fixedPosition = true;
		}
		batch.cullingCollider = bounds;
		batch.name = "modelLibrary";
		batch.material.mainPass.addShader(cache.shader);
		if ( props != null ) {
			batch.material.props = props;
			batch.material.refreshProps();
			if ( (batch.material.props:PbrProps).alphaKill && batch.material.textureShader == null )
				batch.material.mainPass.addShader(killAlpha);
		}
	}

	public function getBakedMat(mat : h3d.mat.Material, prim : h3d.prim.HMDModel, meshName : String) {
		var matName = mat.name;
		matName = reg.replace(matName,'');
		// TODO : optimize string add.
		var bk = bakedMaterials.get(@:privateAccess prim.lib.resource.entry.path + "_" + meshName + "_" + matName);
		if ( bk == null )
			bk = bakedMaterials.get(@:privateAccess prim.lib.resource.entry.path + "_" + matName);
		return bk;
	}

	public function emit(bk : MaterialMesh, batch : h3d.scene.MeshBatch, ?absPos : h3d.Matrix, emitCountTip = -1, ?flags : haxe.EnumFlags<h3d.scene.MeshBatch.MeshBatchFlag> ) {
		cache.shader.uvTransform.set(bk.mat.uvX, bk.mat.uvY, bk.mat.uvSX, bk.mat.uvSY);
		cache.shader.libraryParams.set(bk.mat.texId, 1.0 / btSize / bk.mat.uvSX, 0.0, 0.0);
		if ( batch.primitiveSubPart == null ) {
			batch.primitiveSubPart = new h3d.scene.MeshBatch.MeshBatchPart();
			batch.begin(emitCountTip, flags);
		}
		batch.primitiveSubPart.indexCount = bk.mat.indexCount;
		batch.primitiveSubPart.indexStart = bk.mat.indexStart;
		batch.primitiveSubPart.lodIndexCount = bk.mat.lodIndexCount;
		batch.primitiveSubPart.lodIndexStart = bk.mat.lodIndexStart;
		batch.primitiveSubPart.lodConfig = cast( bk.mesh.primitive, h3d.prim.HMDModel ).getLodConfig();
		batch.primitiveSubPart.bounds = cache.geomBounds[bk.mat.geomId];
		if ( absPos != null )
			batch.worldPosition = absPos;
		batch.emitInstance();
	}

	public function compression() {
		var convert = new hxd.fs.Convert.CompressIMG("png,tga,jpg,jpeg,dds,envd,envs","dds");
		convert.params = {format: "BC3"};
		var path = new haxe.io.Path(Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem).baseDir+shared.currentPath);
		path.ext = "dat";
		var datDir = path.toString() + '/${name}/';
		convert.dstPath = datDir;
		if ( !hxd.res.Loader.currentInstance.exists(convert.dstPath) )
			sys.FileSystem.createDirectory(convert.dstPath);
		function convertFile(name:String) {
			update("Compress "+name);
			var filename =  name + ".dds";
			convert.srcPath = datDir + filename;
			convert.originalFilename = filename;
			convert.srcBytes = hxd.File.getBytes(convert.srcPath);
			convert.convert();
			var success = false;
			for ( fmt in ["BC1", "BC3", "dds_BC1", "dds_BC3"] ) {
				try {
					var compressedTex = datDir + name + "_" + fmt + ".dds";
					if ( sys.FileSystem.exists(compressedTex) )
						sys.FileSystem.deleteFile(convert.srcPath);
					sys.FileSystem.rename(compressedTex, convert.srcPath);
					success = true;
					break;
				} catch (e :Dynamic) {}
			}
			if ( !success )
				throw "Failed to replace compressed texture in " + datDir + " to " + convert.srcPath;
		}
		convertFile("texture");
		convertFile("normal");
		convertFile("specular");
	}

	#if editor
	override function edit(ectx:hide.prefab.EditContext) {

		ectx.properties.add(new hide.Element('
		<div class="group" name="Params">
			<dl>
				<dt>Miplevels</dt><dd><input type="range" step="1" field="mipLevels"/></dd>
				<dt>Distance start</dt><dd><input type="range" field="mipStart"/></dd>
				<dt>Distance end</dt><dd><input type="range" field="mipEnd"/></dd>
				<dt>Power</dt><dd><input type="range" field="mipPower"/></dd>
			</dl>
		</div>'), this, function(pname) {
			ectx.onChange(this, pname);
		});

		var bt = new hide.Element('<div align="center"><input type="button" value="Build"/></div>');
		bt.find("input").click(function(e) {
			ectx.makeChanges(this, function() {
				errors = [];
				rebuildData();
				if ( compress )
					compression();

				var ide = hide.Ide.inst;
				ide.setProgress();
				if( errors.length > 0 )
					ide.error(errors.join("\n"));
			});
		});
		ectx.properties.add(bt);

		ectx.properties.add(new hide.Element('
		<div class="group" name="Compression">
			<dl>
				<dt>Compress During Build</dt><dd><input type="checkbox" field="compress"/></dd>
			</dl>
		</div>'), this, function(pname) {
			ectx.onChange(this, pname);
		});

		var bt = new hide.Element('<div align="center"><input type="button" value="CompressOnly"/></div>');
		bt.find("input").click(function(e) {
			ectx.makeChanges(this, function() {
				errors = [];
				compression();

				var ide = hide.Ide.inst;
				ide.setProgress();
				if( errors.length > 0 )
					ide.error(errors.join("\n"));
			});
		});
		ectx.properties.add(bt);

		var listMaterials = new hide.Element('
		<div class="group" name="Ignored materials"><ul id="ignoreMatList"></ul></div>');
		ectx.properties.add(listMaterials);
		for( i in 0...ignoredMaterials.length ) {
			var e = new hide.Element('<li style="position:relative">
				<input type="text" field="name"/>
				<a href="#">[-]</a>
			</li>');
			e.find("a").click(function(_) {
				ignoredMaterials.splice(i, 1);
				ectx.rebuildProperties();
			});
			e.appendTo(listMaterials);
			ectx.properties.build(e, ignoredMaterials[i], (pname) -> {
				updateInstance(pname);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(listMaterials);
		add.find("a").click(function(_) {
			ignoredMaterials.push({name:""});
			ectx.rebuildProperties();
		});

		var listPrefabs = new hide.Element('
		<div class="group" name="Ignored prefabs"><ul id="ignorePrefabList"></ul></div>');
		ectx.properties.add(listPrefabs);
		for( i in 0...ignoredPrefabs.length ) {
			var e = new hide.Element('<li style="position:relative">
				<input type="text" field="name"/>
				<a href="#">[-]</a>
			</li>');
			e.find("[field=name]");
			e.find("a").click(function(_) {
				ignoredPrefabs.splice(i, 1);
				ectx.rebuildProperties();
			});
			e.appendTo(listPrefabs);
			ectx.properties.build(e, ignoredPrefabs[i], (pname) -> {
				updateInstance(pname);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(listPrefabs);
		add.find("a").click(function(_) {
			ignoredPrefabs.push({name:null});
			ectx.rebuildProperties();
		});

		var listObjectNames = new hide.Element('
		<div class="group" name="Ignored object names"><ul id="ignoreObjectNames"></ul></div>');
		ectx.properties.add(listObjectNames);
		for( i in 0...ignoredObjectNames.length ) {
			var e = new hide.Element('<li style="position:relative">
				<input type="text" field="name"/>
				<a href="#">[-]</a>
			</li>');
			e.find("a").click(function(_) {
				ignoredObjectNames.splice(i, 1);
				ectx.rebuildProperties();
			});
			e.appendTo(listObjectNames);
			ectx.properties.build(e, ignoredObjectNames[i], (pname) -> {
				updateInstance(pname);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(listObjectNames);
		add.find("a").click(function(_) {
			ignoredObjectNames.push({name:""});
			ectx.rebuildProperties();
		});

		var listpreserveObjectNames = new hide.Element('
		<div class="group" name="Preserve object names"><ul id="preserveObjectNames"></ul></div>');
		ectx.properties.add(listpreserveObjectNames);
		for( i in 0...preserveObjectNames.length ) {
			var e = new hide.Element('<li style="position:relative">
				<input type="text" field="name"/>
				<a href="#">[-]</a>
			</li>');
			e.find("a").click(function(_) {
				preserveObjectNames.splice(i, 1);
				ectx.rebuildProperties();
			});
			e.appendTo(listpreserveObjectNames);
			ectx.properties.build(e, preserveObjectNames[i], (pname) -> {
				updateInstance(pname);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(listpreserveObjectNames);
		add.find("a").click(function(_) {
			preserveObjectNames.push({name:""});
			ectx.rebuildProperties();
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "square", name : "Model Library" };
	}
	#end

	static var _ = Prefab.register("modelLib", ModelLibrary);

}