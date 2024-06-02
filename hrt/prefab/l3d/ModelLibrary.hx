package hrt.prefab.l3d;
import h3d.mat.PbrMaterial;
import hxd.fmt.hmd.Data;

typedef MaterialData = {
	var indexStart : Int;
	var indexCount : Int;
	var geomId : Int;
	var texId : Int;
	var uvX : Float;
	var uvY : Float;
	var uvSX : Float;
	var uvSY : Float;
	var configIndex : Int;
}

typedef MaterialMesh = {
	mat : MaterialData,
	mesh : h3d.scene.Mesh,
}
typedef SubMeshes = {
	meshes : Array<MaterialMesh>,
	name : String,
}

class ModelLibShader extends hxsl.Shader {
	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@param @perInstance var uvTransform : Vec4;
		@param @perInstance var material : Float;
		@param @perInstance var delta : Float;

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
			if( hasNormal )
				transformedTangent = vec4(input2.tangent * global.modelView.mat3(),input2.tangent.dot(input2.tangent) > 0.5 ? 1. : -1.);
			mipLevel = pow(saturate((projectedPosition.z - mipStart) / (mipEnd - mipStart)), mipPower) * mipNumber;
		}

		function __init__fragment() {
			calculatedUV = clamp(input2.uv.fract(), delta, 1.0 - delta);
			calculatedUV = calculatedUV * uvTransform.zw + uvTransform.xy;
			pixelColor = singleTexture ? texture.getLod(calculatedUV, mipLevel) : textures.getLod(vec3(calculatedUV, material), mipLevel);
			if( hasNormal ) {
				var n = transformedNormal;
				var nf = unpackNormal(singleTexture ? normalMap.getLod(calculatedUV, mipLevel) : normalMaps.getLod(vec3(calculatedUV, material), mipLevel));
				var tanX = transformedTangent.xyz.normalize();
				var tanY = n.cross(tanX) * -transformedTangent.w;
				transformedNormal = (nf.x * tanX + nf.y * tanY + nf.z * n).normalize();
			}
			if( hasPbr ) {
				var v = singleTexture ? specular.getLod(calculatedUV, mipLevel) : speculars.getLod(vec3(calculatedUV, material), mipLevel);
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
	@:s var materialConfigs : Array<h3d.mat.PbrMaterial.PbrProps> = [];
	@:s var texturesCount : Int;

	var optimizedMeshes : Array<h3d.scene.Mesh> = [];
	var batches : Array<h3d.scene.MeshBatch> = [];

	@:s var ignoredMaterials : Array<{name:String}> = [];
	@:s var ignoredPrefabs : Array<{name:String}> = [];
	@:s var ignoredObjectNames : Array<{name:String}> = [];
	@:s var preserveObjectNames : Array<{name:String}> = [];

	@:s var mipEnd : Float;
	@:s var mipStart : Float;
	@:s var mipPower : Float;
	@:s var mipLevels : Int = 1;

    final reg = ~/[0-9]+/g;

	override public function dispose() {
		super.dispose();
		optimizedMeshes = [];
		batches = [];
	}

	var cache : ModelLibraryCache;
	public function new(prefab, shared) {
		super(prefab, shared);
		cache = new ModelLibraryCache();
	}

	#if editor

	@:s var compress : Bool = true;

	var errors = [];

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
				rebuildData(ectx.scene);
				if ( compress )
					compression(ectx.scene);

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
				compression(ectx.scene);

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

	function update( text : String ) {
		hide.Ide.inst.setProgress(text);
	}

	function rebuildData(scene : hide.comp.Scene ) {

		bakedMaterials = {};
		materialConfigs = [];

		var btSize = 4096;
		var ide = hide.Ide.inst;

		var hmd = new Data();
		hmd.version = Data.CURRENT_VERSION;
		hmd.geometries = [];
		hmd.materials = [];
		hmd.models = [];
		hmd.animations = [];
		hmd.shapes = [];
		var models = new Map();
		var dataOut = new haxe.io.BytesBuffer();

		var textures : Array<h3d.mat.BigTexture> = [];
		var normalMaps : Array<h3d.mat.BigTexture> = [];
		var specMaps : Array<h3d.mat.BigTexture> = [];
		var tmap = new Map();

		function allocDefault(name,color,alpha=1) {
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

		function error( text : String ) {
			errors.push(text);
		}

		function loadTexture( sourcePath, texPath, normalMap, specMap ) {

			var t = null;
			if ( texPath == null )
				return null;
			var tmp = scene.loadTexture(sourcePath, texPath);

			var ntex = normalMap == null ? null : scene.loadTexture(sourcePath, normalMap);
			var stex = specMap == null ? null : scene.loadTexture(sourcePath, specMap);
			var key = texPath+"/"+(ntex==null?"nonorm":ntex.name)+(stex==null?"nospec":stex.name);
			t = tmap.get(key);
			if( t != null )
				return t;
			update("Packing "+key);
			var realTex = hxd.res.Any.fromBytes(tmp.name, tmp == whiteDefault.tex ? whiteDefault.bytes : sys.io.File.getBytes(ide.getPath(tmp.name))).toImage();
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
					var texBytes = if( tex == normalDefault.tex ) normalDefault.bytes else if( tex == specDefault.tex ) specDefault.bytes else sys.io.File.getBytes(ide.getPath(tex.name));
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

				var heapsMat = @:privateAccess lib.makeMaterial(lib.header.models[mid], mid, function(path:String) { return scene.loadTexture(sourcePath, path);});
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

				var pos = loadTexture(sourcePath, diffuseTexture, normalMap, specularTexture);
				if ( pos == null )
					return null;
				var matName = m.name;
				matName = reg.replace(matName, '');
				var key = lib.resource.entry.path + (modelName != "root" ? "_" + modelName : "") + "_" + matName;
				var bk = bakedMaterials.get(key);
				if ( bk != null )
					return bk;
				var matConfigIndex = -1;
				for ( i in 0...materialConfigs.length ) {
					if ( haxe.Json.stringify((heapsMat.props:PbrProps)) == haxe.Json.stringify(materialConfigs[i]) ) {
							matConfigIndex = i;
							break;
						}
					}
					if ( matConfigIndex < 0 ) {
						materialConfigs.push((heapsMat.props:PbrProps));
						matConfigIndex = materialConfigs.length - 1;
					}
					bk = {
						indexStart : 0,
						indexCount : 0,
						geomId : 0,
						texId : hxd.Math.floor(pos.tex.id / mipLevels),
						uvX : pos.pos.du,
						uvY : pos.pos.dv,
						uvSX : pos.pos.su,
						uvSY : pos.pos.sv,
						configIndex : matConfigIndex,
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
		geomAll.vertexCount = currentVertex;
		geomAll.vertexPosition = dataOut.length;
		if( geomAll.vertexFormat.stride < 3 ) {
			ide.error("No model found in data");
			return;
		}
		for( inf in dataToStore ) {
			var g = inf.g;
			g.vertexPosition = dataOut.length;
			var buf = inf.lib.getBuffers(inf.origin, geomAll.vertexFormat, [for( v in geomAll.vertexFormat.getInputs() ) new h3d.Vector4(0,0,0,0)]);
			for( i in 0...geomAll.vertexFormat.stride * inf.origin.vertexCount )
				dataOut.addFloat(buf.vertexes[i]);
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
				if( write16 ) {
					var v = idx + inf.offset;
					dataOut.addByte(v&0xFF);
					dataOut.addByte(v>>8);
				} else
					dataOut.addInt32(idx + inf.offset);
			}
		}

		hmd.data = dataOut.getBytes();
		var out = new haxe.io.BytesOutput();
		var w = new hxd.fmt.hmd.Writer(out);
		w.write(hmd);
		var bytes = out.getBytes();
		shared.savePrefabDat("model","hmd",name,bytes);

		texturesCount = textures.length;
		function make(textures:Array<h3d.mat.BigTexture>, name : String ) {
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
		make(textures,"texture");
		make(normalMaps,"normal");
		make(specMaps,"specular");
	}

	function compression(scene : hide.comp.Scene ) {
		var convert = new hxd.fs.Convert.CompressIMG("png,tga,jpg,jpeg,dds,envd,envs","dds");
		convert.params = {format: "BC3"};
		var path = new haxe.io.Path(Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem).baseDir+shared.currentPath);
		path.ext = "dat";
		var datDir = path.toString() + "/modelLib/";
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
					sys.FileSystem.rename(datDir + name + "_" + fmt + ".dds", convert.srcPath);
					success = true;
				} catch (e :Dynamic) {}
			}
			if ( !success )
				throw "Failed to replace compressed texture in " + datDir + " to " + convert.srcPath;
		}
		convertFile("texture");
		convertFile("normal");
		convertFile("specular");
	}

	#else

	// var shared : hrt.prefab.ContextShared;

	public var debug = false;
	public var clear = false;

	override function make(?sh:hrt.prefab.Prefab.ContextMake) : hrt.prefab.Prefab {
		// don't load/build children
		if (cache.wasMade)
			return this;

		cache.wasMade = true;
		if ( cache.hmdPrim == null )
			cache.hmdPrim = Std.downcast(shared.loadModel(shared.getPrefabDatPath("model","hmd",this.name)).toMesh().primitive, h3d.prim.HMDModel);
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

	override function clone(?parent:Prefab = null, ?sh: ContextShared = null, withChildren : Bool = true) : Prefab {
		var clone : ModelLibrary = cast super.clone(parent, sh, withChildren);
		clone.cache = cache;
		return clone;
	}


	// public function dispose() {
	// 	optimizedMeshes = [];
	// 	batches = [];
	// }

	var killAlpha = new h3d.shader.KillAlpha(0.5);
	var curSubMeshes : SubMeshes = null;
	public function optimize( obj : h3d.scene.Object, isStatic = true ) {
		if( bakedMaterials == null )
			throw "Model library was not built or saved";
		if( !cache.wasMade )
			throw "Please call make() on modelLibrary first";

		var meshBatches = [for (i in 0...materialConfigs.length * (preserveObjectNames.length + 1)) null];
		for( c in obj ) {
			var ms = Std.downcast(c, h3d.scene.MeshBatch);
			if( ms != null && ms.name.indexOf("modelLibrary") == 0 ) {
				var index = ms.name.split("_")[1];
				if ( meshBatches[Std.parseInt(index)] == null )
					meshBatches[Std.parseInt(index)] = ms;
			}
		}

		var subMeshes : Array<SubMeshes> = [{meshes : [], name : ""}];
		for ( name in preserveObjectNames ) {
			subMeshes.push({meshes : [], name : name.name});
		}
		var bounds = obj.getBounds();
		curSubMeshes = subMeshes[0];
		optimizeRec(obj, subMeshes);
		var indexOffset = 0;
		for ( meshes in subMeshes ) {
			var namedObject = new h3d.scene.Object(obj);
			namedObject.name = meshes.name;
			meshes.meshes.sort(function(m1,m2) return m1.mat.indexStart - m2.mat.indexStart);
			for ( m in meshes.meshes ) {
				var bk = m.mat;
				if ( meshBatches[bk.configIndex + indexOffset] == null) {
					var batch = createMeshBatch(namedObject, isStatic, bounds, materialConfigs[bk.configIndex]);
					batch.name += "_"+(bk.configIndex + indexOffset);
					if ( debug ) batches.push(batch);
					meshBatches[bk.configIndex + indexOffset] = batch;
				}
			}
			for( m in meshes.meshes ) {
				var bk = m.mat;
				var batch = meshBatches[bk.configIndex + indexOffset];
				emit(m, batch);
			}
			indexOffset += materialConfigs.length;
		}

		for (batch in meshBatches ) {
			if ( batch != null ) {
				batch.primitiveSubPart = null;
			}
		}
		if ( !debug && clear )
			clearOptimized(obj);
	}

	public function createMeshBatch(parent : h3d.scene.Object, isStatic : Bool, ?bounds : h3d.col.Bounds, ?props : h3d.mat.PbrMaterial.PbrProps) {
		var batch = new h3d.scene.MeshBatch(cache.hmdPrim, h3d.mat.Material.create(), parent);
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
		return batch;
	}

	function optimizeRec( obj : h3d.scene.Object, out : Array<SubMeshes> ) {
		if( !obj.visible )
			return;
		for ( n in ignoredObjectNames ) {
			if ( n.name == obj.name )
				return;
		}
		var prevSubMeshes = curSubMeshes;
		for ( name in preserveObjectNames ) {
			if ( obj.name != null && obj.name == name.name ) {
				curSubMeshes = out.filter(s -> s.name == name.name)[0];
				break;
			}
		}
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		if( mesh != null ) {
			for ( shader in ignoredPrefabs) {
				var cl : Class<hxsl.Shader> = cast Type.resolveClass(shader.name);
				if( cl != null ) {
					for ( p in mesh.material.getPasses() ) {
						if ( p.getShader(cl) != null )
							return;
					}
				}
			}
			var prim = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
			if( prim != null ) {
				var mat = mesh.getMaterials(false);
				mesh.culled = true;
				for ( m in mat ) {
					var bk = getBakedMat(m, prim, mesh.name);
					if( bk == null ) {
						mesh.culled = false;
						while( curSubMeshes.meshes.length > 0 && curSubMeshes.meshes[curSubMeshes.meshes.length-1].mesh == mesh )
							curSubMeshes.meshes.pop();
						break;
					}
					curSubMeshes.meshes.push({ mat : bk, mesh : mesh });
				}
				if ( mesh.culled && debug )
					optimizedMeshes.push(mesh);
			}
		}
		for( o in obj )
			optimizeRec(o, out);
		curSubMeshes = prevSubMeshes;
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

	function clearOptimized(obj: h3d.scene.Object) {
		for ( c in @:privateAccess obj.children.copy() ) {
			clearOptimized(c);
		}
		if ( @:privateAccess obj.children.length == 0 && ((Std.isOfType(obj, h3d.scene.Mesh) && obj.culled) || Type.getClass(obj) == h3d.scene.Object) )
			obj.remove();
	}

	function toggle() {
		enabled = !enabled;
		for (m in optimizedMeshes)
			m.culled = enabled;
		for (b in batches)
			b.culled = !enabled;
	}

	function hideAll() {
		for (m in optimizedMeshes)
			m.culled = true;
		for (b in batches)
			b.culled = true;
	}

	public function emit(m : MaterialMesh, batch : h3d.scene.MeshBatch, emitCountTip = -1) {
		var bk = m.mat;
		cache.shader.delta = 1.0 / 4096 / bk.uvSX;
		cache.shader.uvTransform.set(bk.uvX, bk.uvY, bk.uvSX, bk.uvSY);
		cache.shader.material = bk.texId;
		if ( batch.primitiveSubPart == null ) {
			batch.primitiveSubPart = new h3d.scene.MeshBatch.MeshBatchPart();
			batch.begin(emitCountTip);
		}
		batch.primitiveSubPart.indexCount = bk.indexCount;
		batch.primitiveSubPart.indexStart = bk.indexStart;
		batch.primitiveSubPart.bounds = cache.geomBounds[bk.geomId];
		batch.worldPosition = m.mesh.getAbsPos();
		batch.emitInstance();
	}

	#end

	static var _ = Prefab.register("modelLib", ModelLibrary);

}