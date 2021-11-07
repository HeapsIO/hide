package hrt.prefab.l3d;
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
}

class ModelLibShader extends hxsl.Shader {
	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@param @perInstance var uvTransform : Vec4;
		@param @perInstance var material : Float;

		@const var singleTexture : Bool;
		@const var hasNormal : Bool;
		@const var hasPbr : Bool;

		@param var texture : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var specular : Sampler2D;

		@param var textures : Sampler2DArray;
		@param var normalMaps : Sampler2DArray;
		@param var speculars : Sampler2DArray;


        @input var input2 : {
			var tangent : Vec3;
			var uv : Vec2;
        };


		var calculatedUV : Vec2;
		var transformedTangent : Vec4;

		var metalness : Float;
		var roughness : Float;
		var occlusion : Float;

		function __init__vertex() {
			if( hasNormal )
				transformedTangent = vec4(input2.tangent * global.modelView.mat3(),input2.tangent.dot(input2.tangent) > 0.5 ? 1. : -1.);
		}

		function __init__fragment() {
			calculatedUV = input2.uv.fract() * uvTransform.zw + uvTransform.xy;
			pixelColor *= singleTexture ? texture.get(calculatedUV) : textures.get(vec3(calculatedUV, material));
			if( hasNormal ) {
				var n = transformedNormal;
				var nf = unpackNormal(singleTexture ? normalMap.get(calculatedUV) : normalMaps.get(vec3(calculatedUV, material)));
				var tanX = transformedTangent.xyz.normalize();
				var tanY = n.cross(tanX) * -transformedTangent.w;
				transformedNormal = (nf.x * tanX + nf.y * tanY + nf.z * n).normalize();
			}
			if( hasPbr ) {
				var v = singleTexture ? specular.get(calculatedUV) : speculars.get(vec3(calculatedUV, material));
				metalness = v.r;
				roughness = 1 - v.g * v.g;
				occlusion = v.b;
				// no emissive for now
			}
		}

	}
}

class ModelLibrary extends Prefab {

	@:s var bakedMaterials : haxe.DynamicAccess<MaterialData>;
	@:s var texturesCount : Int;
	@:s var renamedMaterials : haxe.DynamicAccess<haxe.DynamicAccess<String>>;

	#if editor

	override function makeInstance(ctx) {
		return ctx.clone(this);
	}

	override function edit(ectx:hide.prefab.EditContext) {
		var bt = new Element('<div align="center"><input type="button" value="Build"/></div>');
		var ctx = ectx.getContext(this);
		bt.find("input").click(function(e) {
			ectx.makeChanges(this, function() {
				rebuildData(ctx.shared, ectx.scene);
			});
		});
		ectx.properties.add(bt);
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Model Library" };
	}

	function rebuildData( shared : ContextShared, scene : hide.comp.Scene ) {

		bakedMaterials = {};
		renamedMaterials = null;

		var btSize = 4096;
		var ide = hide.Ide.inst;

		var hmd = new Data();
		hmd.version = Data.CURRENT_VERSION;
		hmd.geometries = [];
		hmd.materials = [];
		hmd.models = [];
		hmd.animations = [];
		var models = new Map();
		var dataOut = new haxe.io.BytesBuffer();
		var dataPath = new haxe.io.Path(shared.currentPath);
		dataPath.ext = "dat";
		var dataPath = dataPath.toString()+"/"+name+"/";

		var textures : Array<h3d.mat.BigTexture> = [];
		var normalMaps : Array<h3d.mat.BigTexture> = [];
		var specMaps : Array<h3d.mat.BigTexture> = [];
		var tmap = new Map();
		var materialSources = new Map();
		var hasNormal = false, hasSpec = false;

		function update( text : String ) {
			ide.setProgress(text);
		}

		function error( text : String ) {
			ide.error(text);
		}

		function loadTexture( sourcePath, texPath, normalMap, specMap ) {

			if( texPath == null )
				throw "Missing texture";

			var tex = scene.loadTexture(sourcePath, texPath);
			if( tex == null ) throw "Missing texture "+sourcePath+"("+texPath+")";

			var ntex = normalMap == null ? null : scene.loadTexture(sourcePath, normalMap);
			var stex = specMap == null ? null : scene.loadTexture(sourcePath, specMap);
			var key = tex.name+"/"+(ntex==null?"nonorm":ntex.name)+(stex==null?"nospec":stex.name);

			var t = tmap.get(key);
			if( t != null )
				return t;
			update("Packing "+key);
			var texPath = tex.name;
			var realTex = hxd.res.Any.fromBytes(tex.name, sys.io.File.getBytes(ide.getPath(tex.name))).toImage();
			var pos = null, posTex = null;
			for( i in 0...textures.length ) {
				var b = textures[textures.length - 1 - i];
				pos = b.add(realTex);
				if( pos != null ) {
					posTex = b;
					break;
				}
			}
			if( pos == null ) {
				var b = new h3d.mat.BigTexture(textures.length, btSize, 0);
				textures.push(b);
				pos = b.add(realTex);
				posTex = b;
			}
			t = {
				pos : pos,
				tex : posTex,
			};

			function packSub(textures:Array<h3d.mat.BigTexture>, tex : h3d.mat.Texture, isSpec ) {
				var t = textures[posTex.id];
				if( t == null ) {
					t = new h3d.mat.BigTexture(textures.length, btSize, 0);
					textures[posTex.id] = t;
				}
				var inf = realTex.getInfo();
				if( tex == null ) {
					var path = isSpec ? specMap : normalMap;
					if( path != null )
						error('Missing texture $sourcePath($path)');
					else
						error('$sourcePath material is missing ${isSpec?"specular":"normal"} texture set');
					t.addEmpty(inf.width, inf.height);
					return;
				}
				var realTex = hxd.res.Any.fromBytes(tex.name, sys.io.File.getBytes(ide.getPath(tex.name))).toImage();
				var inf2 = realTex.getInfo();
				if( inf2.width != inf.width || inf2.height != inf.height ) {
					error([
						(isSpec?"Specular texture ":"Normal map ")+" has size not matching the albedo",
						"Texture: "+tex.name+'(${inf2.width}x${inf2.height})',
						"Albedo: "+texPath+'(${inf.width}x${inf.height})',
						"Model: "+sourcePath
					].join("\n"));
					t.addEmpty(inf.width, inf.height);
					return;
				}
				t.add(realTex);
			}

			packSub(normalMaps, ntex, false);
			packSub(specMaps, stex, true);

			tmap.set(key, t);
			return t;
		}

		var indexStarts = [], currentIndex = 0, currentVertex = 0;
		var dataToStore = [];

		var geomAll = new Geometry();
		geomAll.bounds = new h3d.col.Bounds();
		geomAll.bounds.addPos(0,0,0);
		geomAll.vertexStride = -1;
		geomAll.indexCounts = [];
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

		for( m in getAll(hrt.prefab.Model, true) ) {
			if( models.exists(m.source) )
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

			var libData = lib.getData();

			function addMaterial( m : Material ) {
				var m2 = new Material();
				m2.name = m.name;
				m2.props = m.props;
				m2.blendMode = m.blendMode;

				if( textures.length == 0 ) {
					hasNormal = m.normalMap != null;
					hasSpec = m.specularTexture != null;
				}

				var pos = loadTexture(sourcePath, m.diffuseTexture, hasNormal ? m.normalMap : null, hasSpec ? m.specularTexture : null);
				var bk = bakedMaterials.get(m.name);
				var renIndex = 2;
				while( bk != null ) {
					m2.name = m.name+"_"+(renIndex++);
					bk = bakedMaterials.get(m2.name);
				}

				if( m.name != m2.name ) {
					//trace("Material "+sourcePath+"("+m.name+") conflicts with "+materialSources.get(m.name)+", renaming to "+m2.name);
					if( renamedMaterials == null )
						renamedMaterials = {};
					var ml = renamedMaterials.get(m.name);
					if( ml == null ) {
						ml = {};
						renamedMaterials.set(m.name, ml);
					}
					ml.set(sourcePath, m2.name);
				}
				materialSources.set(m2.name, sourcePath);
				bk = {
					indexStart : 0,
					indexCount : 0,
					geomId : 0,
					texId : pos.tex.id,
					uvX : pos.pos.du,
					uvY : pos.pos.dv,
					uvSX : pos.pos.su,
					uvSY : pos.pos.sv,
				};
				bakedMaterials.set(m2.name, bk);

				if( !hasNormal && m.normalMap != null )
					error(sourcePath+"("+m.name+") has normal map texture");

				if( !hasSpec && m.specularTexture != null )
					error(sourcePath+"("+m.name+") has specular texture");

				hmd.materials.push(m2);
				return bk;
			}

			var offsetGeom = hmd.geometries.length;
			var offsetModels = hmd.models.length;

			for( g in lib.header.geometries ) {

				if( geomAll.vertexStride < 0 ) {
					geomAll.vertexStride = g.vertexStride;
					geomAll.vertexFormat = g.vertexFormat;
				}

				if( g.vertexStride != geomAll.vertexStride ) throw "ABORT : Mixed vertex stride";

				var g2 = new Geometry();
				g2.props = g.props;
				g2.vertexCount = 0;
				g2.vertexStride = g.vertexStride;
				g2.vertexFormat = g.vertexFormat;
				g2.indexCounts = [];
				g2.vertexPosition = g.vertexPosition;
				g2.indexPosition = g.indexPosition;
				g2.bounds = g.bounds;
				hmd.geometries.push(g2);

				dataToStore.push({ g : g2, data : libData, vertexCount : g.vertexCount, indexCount : g.indexCount, offset : currentVertex });
				currentVertex += g.vertexCount;

				var arr = [];
				for( i in g.indexCounts ) {
					arr.push(currentIndex);
					currentIndex += i;
					geomAll.indexCounts.push(i);
				}
				indexStarts.push(arr);
			}

			for( m in lib.header.models ) {
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
						var mat = addMaterial(lib.header.materials[mid]);
						mat.geomId = m2.geometry;
						mat.indexCount = lib.header.geometries[m.geometry].indexCounts[index];
						mat.indexStart = indexStarts[m2.geometry][index];
						m2.materials.push(hmd.materials.length - 1);
					}
				}
				if( m.skin != null )
					error("Not supported: "+sourcePath+"("+m.name+") has skin");
				hmd.models.push(m2);
			}
			/*
			if( lib.header.animations.length > 0 ) {
				var noAnim = new haxe.EnumFlags<AnimationFlag>();
				noAnim.set(SingleFrame);
				noAnim.set(HasPosition);
				for( a in lib.header.animations ) {
					if( a.objects.length == 1 && a.objects[0].flags == noAnim ) {
						var x = libData.getFloat(a.dataPosition);
						var y = libData.getFloat(a.dataPosition + 4);
						var z = libData.getFloat(a.dataPosition + 8);
						if( x == 0 && y == 0 && z == 0 )
							continue;
					}
					hide.Ide.inst.error(sourceName+" has animation data that will be ignore");
					break;
				}
			}
			*/
		}

		modelRoot.materials = [for( i in 0...hmd.materials.length ) i];

		geomAll.vertexCount = currentVertex;
		geomAll.vertexPosition = dataOut.length;
		for( inf in dataToStore ) {
			var g = inf.g;
			var dataPos = g.vertexPosition;
			g.vertexPosition = dataOut.length;
			dataOut.addBytes(inf.data, dataPos, g.vertexStride * inf.vertexCount * 4);
		}

		geomAll.indexPosition = dataOut.length;
		for( inf in dataToStore ) {
			var g = inf.g;
			var dataPos = g.indexPosition;
			g.indexPosition = dataOut.length;
			var read16 = inf.vertexCount <= 0x10000;
			var write16 = geomAll.vertexCount <= 0x10000;
			for( i in 0...inf.indexCount ) {
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

		ide.setProgress();
	}

	#else

	var shared : hrt.prefab.ContextShared;
	var hmdPrim : h3d.prim.HMDModel;
	var shader : ModelLibShader;
	var geomBounds : Array<h3d.col.Bounds>;

	override function make(ctx:hrt.prefab.Context) {
		// don't load/build children
		shared = ctx.shared;
		hmdPrim = Std.downcast(shared.loadModel(shared.getPrefabDatPath("model","hmd",this.name)).toMesh().primitive, h3d.prim.HMDModel);
		geomBounds = [for( g in @:privateAccess hmdPrim.lib.header.geometries ) g.bounds];
		@:privateAccess hmdPrim.curMaterial = -1;
		shader = new ModelLibShader();
		var tex = shared.loadTexture(shared.getPrefabDatPath("texture","dds",this.name));
		var tnormal = try shared.loadTexture(shared.getPrefabDatPath("normal","dds",this.name)) catch( e : hxd.res.NotFound ) null;
		var tspec = try shared.loadTexture(shared.getPrefabDatPath("specular","dds",this.name)) catch( e : hxd.res.NotFound ) null;
		if( texturesCount == 1 ) {
			shader.singleTexture = true;
			shader.texture = tex;
			shader.normalMap = tnormal;
			shader.specular = tspec;
		} else {
			shader.textures = cast(tex,h3d.mat.TextureArray);
			shader.normalMaps = cast(tnormal,h3d.mat.TextureArray);
			shader.speculars = cast(tspec,h3d.mat.TextureArray);
		}
		shader.hasNormal = tnormal != null;
		shader.hasPbr = tspec != null;
		return ctx;
	}

	public function optimize( obj : h3d.scene.Object ) {
		if( bakedMaterials == null )
			throw "Model library was not built or saved";
		if( shared == null )
			throw "Please call make() on modelLibrary first";
		var batch = null;
		for( c in obj ) {
			if( c.name == "modelLibrary" ) {
				var ms = Std.downcast(c, h3d.scene.MeshBatch);
				if( ms != null ) {
					batch = ms;
					break;
				}
			}
		}
		if( batch == null ) {
			batch = new h3d.scene.MeshBatch(hmdPrim, h3d.mat.Material.create(), obj);
			batch.material.mainPass.addShader(shader);
		}
		batch.primitiveSubPart = new h3d.scene.MeshBatch.MeshBatchPart();
		batch.begin();
		var meshes = [];
		optimizeRec(batch, obj, meshes);
		meshes.sort(function(m1,m2) return m1.mat.indexStart - m2.mat.indexStart);

		for( m in meshes ) {
			var bk = m.mat;
			shader.uvTransform.set(bk.uvX, bk.uvY, bk.uvSX, bk.uvSY);
			shader.material = bk.texId;
			batch.primitiveSubPart.indexCount = bk.indexCount;
			batch.primitiveSubPart.indexStart = bk.indexStart;
			batch.primitiveSubPart.bounds = geomBounds[bk.geomId];
			batch.worldPosition = m.mesh.getAbsPos();
			batch.emitInstance();
		}

		batch.worldPosition = null;
		batch.primitiveSubPart = null;
	}

	function optimizeRec( batch : h3d.scene.MeshBatch, obj : h3d.scene.Object, out : Array<{ mat : MaterialData, mesh : h3d.scene.Mesh }> ) {
		if( obj == batch )
			return;
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		if( mesh != null ) {
			var prim = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
			if( prim != null ) {
				var mat = mesh.getMaterials(false);
				for( i in 0...mat.length ) {
					var name = mat[i].name;
					if( renamedMaterials != null ) {
						var ml = renamedMaterials.get(name);
						if( ml != null ) {
							var name2 = ml.get(@:privateAccess prim.lib.resource.entry.path);
							if( name2 != null ) name = name2;
						}
					}
					var bk = bakedMaterials.get(name);
					out.push({ mat : bk, mesh : mesh });
				}
				mesh.culled = true;
			}
		}
		for( o in obj )
			optimizeRec(batch, o, out);
	}

	#end

	static var _ = Library.register("modelLib", ModelLibrary);

}