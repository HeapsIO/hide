package hrt.prefab.l3d.modellibrary;

@:access(hrt.prefab.l3d.modellibrary.ModelLibrary)
class Signature {
	var version : Int;
	var rule : String;
	var models : Array<ModelSignature> = [];
	var textures : Array<FileSignature> = [];

	function new() {
	}

	public function computeHash() {
		var content = haxe.Json.stringify(this, "\t");
		return haxe.crypto.Sha1.make(haxe.io.Bytes.ofString(content)).toHex();
	}

	public function save( path : String ) {
		var content = haxe.Json.stringify(this, "\t");
		sys.io.File.saveContent(ModelLibrary.getSystemPath(path), content);
	}

	public static function load( path : String ) : Signature {
		var content = sys.io.File.getContent(ModelLibrary.getSystemPath(path));
		var dyn = try haxe.Json.parse(content) catch( e : Dynamic ) null;
		if( dyn != null ) {
			var sig = new Signature();
			sig.version = dyn.version;
			sig.rule = dyn.rule;
			sig.models = dyn.models;
			sig.textures = dyn.textures;
			return sig;
		}
		return null;
	}

	public static function fromModels( targetPath : String, modelPaths : Array<String> ) : Signature {
		var sig = new Signature();
		sig.version = ModelLibrary.CURRENT_VERSION;
		var dirPath = targetPath.split(".prefab")[0];
		sig.rule = getConvertRuleString(dirPath, "fbx");
		var m = getModelsSignature(modelPaths);
		sig.models = m.models;
		sig.textures = m.textures;
		return sig;
	}

	public static function fromLib( lib : ModelLibrary ) : Signature {
		var sig = new Signature();
		sig.version = ModelLibrary.CURRENT_VERSION;
		sig.rule = lib.meshConvertRule;
		var modelPaths = [for( m in lib.findAll(hrt.prefab.Model, true) ) m.source];
		var m = getModelsSignature(modelPaths);
		sig.models = m.models;
		sig.textures = m.textures;
		return sig;
	}

	static function getConvertRuleString( path : String, ext : String) : String {
		var fs = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		var convRule = @:privateAccess fs.convert.getConvertRule(path+"."+ext);
		return convRule.cmd.paramsStr;
	}

	static function getModelsSignature( modelPaths : Array<String> ) {
		var models = [];
		var textures = [];
		var modelMap : Map<String, Bool> = [];
		var textureMap : Map<String, Bool> = [];
		for( path in modelPaths ) {
			if( modelMap.exists(path) )
				continue;
			modelMap.set(path, true);
			var modelsig = @:privateAccess new ModelSignature(path);
			models.push(modelsig);
			var lib = hxd.res.Loader.currentInstance.load(path).toModel().toHmd();
			for( m in lib.header.materials ) {
				var matsig = getMaterialSignature(lib, m);
				if( matsig == null )
					continue;
				modelsig.materials.push(matsig);
				for( matpath in [matsig.diffuseMapPath, matsig.normalMapPath, matsig.specularMapPath] ) {
					if( matpath != null && !textureMap.exists(matpath) ) {
						textures.push(@:privateAccess new FileSignature(matpath));
						textureMap.set(matpath, true);
					}
				}
			}
		}
		return { models : models, textures : textures };
	}

	static function getMaterialSignature( lib : hxd.fmt.hmd.Library, m : hxd.fmt.hmd.Data.Material ) : MaterialSignature {
		var sig = @:privateAccess new MaterialSignature();
		var mat = h3d.mat.MaterialSetup.current.createMaterial();
		mat.name = m.name;
		mat.model = lib.resource;
		var props = h3d.mat.MaterialSetup.current.loadMaterialProps(mat);
		if( props == null )
			return null;
		if( (props:Dynamic).__ref != null ) {
			var lib = hxd.res.Loader.currentInstance.load((props:Dynamic).__ref).toPrefab().load();
			var m = lib.getOpt(hrt.prefab.Material, (props:Dynamic).name);
			sig.diffuseMapPath = m.diffuseMap;
			sig.normalMapPath = m.normalMap;
			sig.specularMapPath = m.specularMap;
			for ( c in lib.children )
				sig.shaders.push(@:privateAccess c.serialize());
			return sig;
		}
		sig.diffuseMapPath = m.diffuseTexture;
		sig.normalMapPath = m.normalMap;
		sig.specularMapPath = m.specularTexture;
		return sig;
	}
}

@:access(hrt.prefab.l3d.modellibrary.ModelLibrary)
class FileSignature {
	public var path : String;
	public var hash : String;
	function new( path : String ) {
		this.path = path;
		var content = sys.io.File.getBytes(ModelLibrary.getSystemPath(path));
		this.hash = haxe.crypto.Sha1.make(content).toHex();
	}
}

class MaterialSignature {
	public var diffuseMapPath : String;
	public var normalMapPath : String;
	public var specularMapPath : String;
	public var shaders : Array<Dynamic> = [];
	function new() {
	}
}

class ModelSignature extends FileSignature {
	public var materials : Array<MaterialSignature> = [];
	function new( path : String ) {
		super(path);
	}
}