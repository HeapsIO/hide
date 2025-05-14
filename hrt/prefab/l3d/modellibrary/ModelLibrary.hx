package hrt.prefab.l3d.modellibrary;

import h3d.mat.PbrMaterial.PbrProps;
import hxd.fmt.hmd.Data;

typedef BakedMaterialData = {
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
	var materialConfig : Int;
}

class ModelLibraryCache {
	public function new() {};
	public var wasMade = false;
	public var hmdPrim : h3d.prim.HMDModel;
	public var shader : AtlasShader;
	public var geomBounds : Array<h3d.col.Bounds>;
}

class ModelLibrary extends Prefab {

	@:s var bakedMaterials : haxe.DynamicAccess<BakedMaterialData>;
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
	@:s var version : Int = 0;
	@:s var atlasResolution = 4096;
	@:s var autoLod : Bool = false;
	@:s var sighash : String = "";

	public static inline var CURRENT_VERSION = 5;

	var meshEmitters : Map<String, MeshEmitter>;
	// build a cache from primitive to MeshEmitter over the necessary structure from path to MeshEmitter
	var meshEmitterCache : Map<h3d.prim.HMDModel, MeshEmitter>;
	var cache : ModelLibraryCache;
	var shaderKeyCache : Map<String, String>;
	var errors = [];

	var killAlpha = new h3d.shader.KillAlpha(0.5);

	public function new(prefab, shared) {
		super(prefab, shared);
		cache = new ModelLibraryCache();
		meshEmitterCache = new Map();
	}

	#if !editor
	override function clone(?parent:Prefab = null, ?sh: ContextShared = null, withChildren : Bool = true) : Prefab {
		var clone : ModelLibrary = cast super.clone(parent, sh, withChildren);
		clone.cache = cache;
		return clone;
	}
	#end

	var initRuntime : Bool = false;
	public function createBatcher(parent : h3d.scene.Object) {
		if ( meshEmitters == null )
			initMeshEmitters();
		return @:privateAccess new Batcher(parent, this);
	}

	function initMeshEmitters() {
		meshEmitters = new Map();
		for( model in findAll(hrt.prefab.Model, true) ) {
			var cloned = model.clone(false);
			cloned.make();
			var obj = cast(cloned, hrt.prefab.Object3D).local3d;
			for ( m in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh)))
				initMeshEmitter(m);
		}
	}

	function initMeshEmitter( mesh : h3d.scene.Mesh ) {
		var batches : Array<Int> = [];
		var bakedMaterials = [];

		var multiMat = Std.downcast(mesh, h3d.scene.MultiMaterial);
		var meshMaterials = multiMat != null ? multiMat.materials : [mesh.material];
		for ( material in meshMaterials ) {
			var hmdModel = cast(mesh.primitive, h3d.prim.HMDModel);
			var bakedMat = getBakedMat(material, hmdModel, mesh.name);
			if ( bakedMat == null ) {
				var modelPath = @:privateAccess hmdModel.lib.resource.entry.path;
				var libPath = @:privateAccess getPrim().lib.resource.entry.path;
				throw 'Can\'t emit ${modelPath} because ${material.name} was not baked in ${libPath}';
			}
			bakedMaterials.push(bakedMat);
		}
		var meshEmitter = @:privateAccess MeshEmitter.createFromMesh(bakedMaterials, mesh);
		meshEmitters.set(meshEmitterKey(mesh), meshEmitter);
	}

	function getBakedMat(mat : h3d.mat.Material, prim : h3d.prim.HMDModel, meshName : String) {
		var matName = mat.name;
		var bk = bakedMaterials.get(@:privateAccess prim.lib.resource.entry.path + "_" + meshName + "_" + matName);
		if ( bk == null )
			bk = bakedMaterials.get(@:privateAccess prim.lib.resource.entry.path + "_" + matName);
		return bk;
	}

	function getMeshEmitter(mesh : h3d.scene.Mesh) {
		var prim = cast(mesh.primitive, h3d.prim.HMDModel);
		var meshEmitter = meshEmitterCache.get(prim);
		if ( meshEmitter == null ) {
			meshEmitter = meshEmitters.get(meshEmitterKey(mesh));
			meshEmitterCache.set(prim, meshEmitter);
		}
		return meshEmitter;
	}

	function meshEmitterKey(mesh : h3d.scene.Mesh) {
		var prim = cast(mesh.primitive, h3d.prim.HMDModel);
		return @:privateAccess prim.lib.resource.entry.path;
	}

	function emitInstance(bakedMaterial : BakedMaterialData, primitive : h3d.prim.HMDModel, batch : h3d.scene.MeshBatch, ?absPos : h3d.Matrix, emitCountTip = -1) {
		cache.shader.uvTransform.set(bakedMaterial.uvX, bakedMaterial.uvY, bakedMaterial.uvSX, bakedMaterial.uvSY);
		cache.shader.libraryParams.set(bakedMaterial.texId, 1.0 / atlasResolution / bakedMaterial.uvSX, 0.0, 0.0);
		if ( batch.primitiveSubParts == null ) {
			batch.primitiveSubParts = [new h3d.scene.MeshBatch.MeshBatchPart()];
			batch.begin(emitCountTip);
		}
		var primitiveSubPart = batch.primitiveSubParts[0];
		primitiveSubPart.indexCount = bakedMaterial.indexCount;
		primitiveSubPart.indexStart = bakedMaterial.indexStart;
		primitiveSubPart.lodIndexCount = bakedMaterial.lodIndexCount;
		primitiveSubPart.lodIndexStart = bakedMaterial.lodIndexStart;
		primitiveSubPart.lodConfig = primitive.getLodConfig();
		primitiveSubPart.bounds = cache.geomBounds[bakedMaterial.geomId];
		if ( absPos != null )
			batch.worldPosition = absPos;
		batch.emitInstance();
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

	static inline function getSystemPath( path : String ) : String {
		#if editor
		return hide.Ide.inst.getPath(path);
		#else
		return "res/" + path;
		#end
	}

	public function isUpToDate( ?paths : Array<String> ) : Bool {
		if ( version != CURRENT_VERSION ) {
			trace("ModelLibrary is not up to date : version does not match");
			return false;
		}

		var source = shared.prefabSource;
		if ( source == null )
			return false;

		var filePath = getSystemPath(source);
		if ( !sys.FileSystem.exists(filePath) ) {
			trace("ModelLibrary does not exist");
			return false;
		}

		var currentSig = if( paths != null )
				Signature.fromModels(source, paths)
			else
				Signature.fromLib(this);
		if( currentSig.computeHash() != sighash ) {
			trace("ModelLibrary is not up to date : signature mismatch");
			return false;
		}

		return true;
	}

	public function bake() {

		shaderKeyCache = new Map();
		var materialConfigs : Map<String, Int> = new Map();
		var materialConfigLength = 0;
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
				texture.dispose();
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
					var b = new h3d.mat.BigTexture(textures.length, atlasResolution >> mipLevel, 0);
					textures.push(b);
					pos = b.add(mipLevelImage);
					posTex = b;
				}
				inline function atlasError(path : String, image : hxd.res.Image) {
					throw 'Could not atlas ${sourcePath}. ${image.getInfo().width}x${image.getInfo().height} does not fit atlas size ${atlasResolution}x${atlasResolution}';
				}
				if ( pos == null )
					atlasError(sourcePath, mipLevelImage);
				if ( mipLevel == 0) {
					t = {
						pos : pos,
						tex : posTex,
					};
				}

				function packSub(textures:Array<h3d.mat.BigTexture>, tex : h3d.mat.Texture, isSpec ) {
					var t = textures[posTex.id];
					if( t == null ) {
						t = new h3d.mat.BigTexture(textures.length, atlasResolution >> mipLevel, isSpec ? 0xFFFFFF : 0xFF8080FF);
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
					texture.dispose();
					var submiplevelImage = hxd.res.Any.fromBytes(tmp.name+"_"+mipLevel, texBytes).toImage();
					if ( t.add(submiplevelImage) == null )
						atlasError(isSpec ? specMap : normalMap, realTex);
				}

				packSub(normalMaps, ntex, false);
				packSub(specMaps, stex, true);

			}
			tmap.set(key, t);

			tmp.dispose();
			if( ntex != null )
				ntex.dispose();
			if( stex != null )
				stex.dispose();
			return t;
		}

		var indexStarts = [], currentIndex = 0, currentVertex = 0;
		var dataToStore = [];

		var geomAll = new Geometry();
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
				var key = lib.resource.entry.path + (modelName != "root" ? "_" + modelName : "") + "_" + matName;
				var bk = bakedMaterials.get(key);
				if ( bk != null )
					return bk;
				var materialKey = getMaterialKey(heapsMat);
				if ( !materialConfigs.exists(materialKey) ) {
					materialConfigLength++;
					materialConfigs.set(materialKey, materialConfigLength);
				}
				var materialConfig = materialConfigs.get(materialKey);

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
					uvSY : pos.pos.sv,
					materialConfig : materialConfig
				};
				bakedMaterials.set(key, bk);

				hmd.materials.push(m2);
				return bk;
			}

			var offsetGeom = hmd.geometries.length;
			var offsetModels = hmd.models.length;
			var libData = lib.getData();

			for( g in lib.header.geometries ) {

				if( !geomAll.vertexFormat.hasInput("tangent") && g.vertexFormat.hasInput("tangent") )
					geomAll.vertexFormat = geomAll.vertexFormat.append("tangent",DVec3);

				if( !geomAll.vertexFormat.hasInput("color") && g.vertexFormat.hasInput("color") )
					geomAll.vertexFormat = geomAll.vertexFormat.append("color",g.vertexFormat.getInput("color").type);

				var g2 = new Geometry();
				g2.props = g.props;
				g2.vertexCount = 0;
				g2.vertexFormat = g.vertexFormat;
				g2.indexCounts = [];
				g2.bounds = g.bounds;
				geomAll.bounds.add(g2.bounds);
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
				var lods : Array<Model> = null;
				var hasLod = m.lods != null;
				if ( hasLod ) {
					if ( m.isLOD() )
						continue;
					lods = [for ( lod in m.lods) lib.header.models[lod]];
				} else {
					var lodInfos = m.getLODInfos();
					if ( lodInfos.lodLevel > 0 )
						continue;

					if ( lodInfos.lodLevel == 0 )
						lods = lib.findLODs( lodInfos.modelName, m );
				}
				var ignoreModel = false;
				var m2 = new Model();
				m2.name = m.name;
				m2.props = m.props != null ? m.props.copy() : null;
				if ( m2.props != null )
					m2.props.remove(HasCollider);
				m2.parent = m.parent < 0 ? 0 : m.parent + offsetModels;
				m2.follow = m.follow;
				m2.position = m.position;
				m2.geometry = m.geometry < 0 ? -1 : m.geometry + offsetGeom;
				m2.lods = hasLod ? [] : null;
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
						var mat = addMaterial(mid, root ? "root" : m.getObjectName());
						if ( mat != null ) {
							mat.geomId = m2.geometry;
							mat.indexCount = lib.header.geometries[m.geometry].indexCounts[index];
							mat.indexStart = indexStarts[m2.geometry][index];

							if ( hasLod ) {
								mat.lodIndexCount = [];
								mat.lodIndexStart = [];
								mat.lodIndexCount.resize(lods.length);
								mat.lodIndexStart.resize(lods.length);
								for ( i => lod in lods ) {
									var geom = lib.header.geometries[lod.geometry];
									mat.lodIndexCount[i] = geom.indexCounts[index];
									mat.lodIndexStart[i] = indexStarts[lod.geometry + offsetGeom][index];
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
			meshConvertRule = config.cmd.paramsStr;
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

		version = CURRENT_VERSION;
		var sig = Signature.fromLib(this);
		sighash = sig.computeHash();
	}

	function getMaterialKey(material : h3d.mat.Material) {
		var pbrProps = (material.props : PbrProps);
		var key = haxe.Json.stringify(pbrProps);

		var props = h3d.mat.MaterialSetup.current.loadMaterialProps(material);

		if ( props != null ) {
			var matLibPath = (props:Dynamic).__ref;
			if ( matLibPath != null ) {
				var matName = (props:Dynamic).name;
				var shaderKey = shaderKeyCache.get(matName);
				if ( shaderKey == null ) {
					var prefab = hxd.res.Loader.currentInstance.load(matLibPath).toPrefab();
					var libMat = prefab.load().getOpt(hrt.prefab.Material, matName);
					shaderKey = "";
					for ( c in libMat.children )
						shaderKey += haxe.Json.stringify(@:privateAccess c.serialize());
					shaderKeyCache.set(matName, shaderKey);
				}
				key += shaderKey;
			}
		}
		return key;
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
		var modelLib = new hrt.prefab.l3d.modellibrary.ModelLibrary(null, null);
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

		if ( cache.hmdPrim == null )
			cache.hmdPrim = Std.downcast(shared.loadModel(shared.getPrefabDatPath("model","hmd",this.name)).toMesh().primitive, h3d.prim.HMDModel);

		cache.wasMade = true;
		if ( cache.geomBounds == null )
			cache.geomBounds = [for( g in @:privateAccess cache.hmdPrim.lib.header.geometries ) g.bounds];
		@:privateAccess cache.hmdPrim.curMaterial = -1;
		if ( cache.shader == null ) {
			cache.shader = cast(h3d.mat.MaterialSetup.current, h3d.mat.PbrMaterialSetup).createAtlasShader();
			cache.shader.mipStart = mipStart;
			cache.shader.mipEnd = mipEnd;
			cache.shader.mipPower = mipPower;
			cache.shader.mipNumber = mipLevels;
			cache.shader.AUTO_LOD = autoLod;
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

	var forbiddenShaderTypes : Array<Class<hxsl.Shader>> = [h3d.shader.pbr.PropsTexture, h3d.shader.Texture, h3d.shader.NormalMap];
	function isForbiddenShader(s) : Bool {
		for ( type in forbiddenShaderTypes )
			if ( Std.isOfType(s, type ) )
				return true;
		return false;
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
				<dt>Auto texture lod</dt><dd><input type="checkbox" field="autoLod"/></dd>
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
				bake();
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
