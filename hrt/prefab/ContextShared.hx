package hrt.prefab;

#if editor
typedef ContextShared = hide.prefab.ContextShared;
class ContextSharedBase {
#else
class ContextShared {
#end
	public var root2d(default, null) : h2d.Object;
	public var root3d(default, null) : h3d.scene.Object;

	public var currentPath : String;
	public var prefabSource : String = "";

	/**
		When make() is called on prefab, it will instead call customMake on
		each child with current which can either intercept or call make() recursively.
	 **/
	 public var customMake : Prefab -> Void;

	// When make/instanciate is called, this contains the 3d object that should be used as a parent for the newly created object
	// Never modify this in the middle of a instanciate without restoring it after
	public var current3d : h3d.scene.Object = null;

	// When make/instanciate is called, this contains the 2d object that should be used as a parent for the newly created object
	// Never modify this in the middle of a instanciate without restoring it after
	public var current2d : h2d.Object = null;

	// Parent prefab if the object if it was created as a reference
	public var parentPrefab : Prefab = null;

	/**
		Disable some checks at the prefab instanciation time. Used to initialize prefabs that
		don't need locals2d/3d like shaders
	**/
	public var isInstance(default, null) : Bool = false;

	var bakedData : Map<String, haxe.io.Bytes>;

	public function new( ?path : String, ?root2d: h2d.Object = null, ?root3d: h3d.scene.Object = null, isInstance: Bool = true) {
		if( path != null ) prefabSource = currentPath = path;
		this.isInstance = isInstance;
		this.root2d = root2d;
		this.root3d = root3d;

		this.current2d = this.root2d;
		this.current3d = this.root3d;
	}

	public function onError( e : Dynamic ) {
		throw e;
	}

	public function getFolderDatPath() {
		var datPath = new haxe.io.Path(currentPath);
		datPath.ext = "dat";
		return datPath.toString() + "/";
	}

	public function loadDir(p : String, ?dir : String ) : Array<hxd.res.Any> {
		var path = getFolderDatPath() + p;
		if(dir != null) path += "/" + dir;
		return try hxd.res.Loader.currentInstance.dir(path) catch( e : hxd.res.NotFound ) null;
	}

	public function loadPrefabDat(file : String, ext : String, prefab : String) : hxd.res.Any {
		return try hxd.res.Loader.currentInstance.load(getPrefabDatPath(file,ext,prefab)) catch( e : hxd.res.NotFound ) null;
	}

	public function getPrefabDatPath(file : String, ext : String, prefab : String ) {
		var path = new haxe.io.Path(getFolderDatPath() + prefab + "/" + file);
		path.ext = ext;
		return path.toString();
	}

	public function savePrefabDat(file : String, ext : String, prefab : String, bytes : haxe.io.Bytes ) {
		var datDir = getFolderDatPath();
		var instanceDir = datDir + "/" + prefab;

		var prefix = "res/";
		if(!sys.FileSystem.isDirectory(prefix+datDir))
			sys.FileSystem.createDirectory(prefix+datDir);
		if(!sys.FileSystem.isDirectory(prefix+instanceDir))
			sys.FileSystem.createDirectory(prefix+instanceDir);

		var path = new haxe.io.Path("");
		path.dir = instanceDir;
		path.file = file;
		path.ext = ext;
		var file = prefix+path.toString();

		if( bytes == null ){
			try sys.FileSystem.deleteFile(file) catch( e : Dynamic ) {};
			var p = prefix+instanceDir;
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
			var p = prefix+datDir;
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
			return;
		}else{
			sys.io.File.saveBytes(file, bytes);
		}
	}

	public function loadShader( path : String ) : Cache.ShaderDef {
		var r = Cache.get().shaderDefCache.get(path);
		if(r != null)
			return r;
		var cl : Class<hxsl.Shader> = cast Type.resolveClass(path.split("/").join("."));
		if(cl == null) return null;
		// make sure to share the SharedShader instance with the real shader
		// so we don't get a duplicate cache of instances
		var shaderInst = Type.createEmptyInstance(cl);
		@:privateAccess shaderInst.initialize();
		var shader = @:privateAccess shaderInst.shader;
		r = {
			shader: shader,
			inits: []
		};
		Cache.get().shaderDefCache.set(path, r);
		return r;
	}

	public function loadModel( path : String ) {
		return Cache.get().modelCache.loadModel(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	public function loadAnimation( path : String ) {
		return @:privateAccess Cache.get().modelCache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	public function loadTexture( path : String, async : Bool = false ) {
		return Cache.get().modelCache.loadTexture(null, path, async);
	}

	public function loadBytes( file : String) : haxe.io.Bytes {
		return try hxd.res.Loader.currentInstance.load(file).entry.getBytes() catch( e : hxd.res.NotFound ) null;
	}

	public function loadBakedBytes( file : String ) {
		if( bakedData == null ) loadBakedData();
		return bakedData.get(file);
	}

	public function saveBakedBytes( file : String, bytes : haxe.io.Bytes ) {
		if( bakedData == null ) loadBakedData();
		if( bytes == null ) {
			if( !bakedData.remove(file) )
				return;
		} else
			bakedData.set(file, bytes);
		var keys = Lambda.array({ iterator : bakedData.keys });
		if( keys.length == 0 ) {
			saveBakedFile(null);
			return;
		}
		var bytes = new haxe.io.BytesOutput();
		bytes.writeString("BAKE");
		bytes.writeInt32(keys.length);
		var headerSize = 8;
		for( name in keys )
			headerSize += 2 + name.length + 8;
		for( name in keys ) {
			bytes.writeUInt16(name.length);
			bytes.writeString(name);
			bytes.writeInt32(headerSize);
			var len = bakedData.get(name).length;
			bytes.writeInt32(len);
			headerSize += len + 1;
		}
		for( name in keys ) {
			bytes.write(bakedData.get(name));
			bytes.writeByte(0xFE); // stop
		}
		saveBakedFile(bytes.getBytes());
	}

	public function saveTexture( file : String, bytes : haxe.io.Bytes , dir : String, ext : String) {
		throw "Don't know how to save texture";
	}

	function saveBakedFile( bytes : haxe.io.Bytes ) {
		throw "Don't know how to save baked file";
	}

	function loadBakedFile() {
		var path = new haxe.io.Path(currentPath);
		path.ext = "bake";
		return try hxd.res.Loader.currentInstance.load(path.toString()).entry.getBytes() catch( e : hxd.res.NotFound ) null;
	}

	function loadBakedData() {
		bakedData = new Map();
		var data = loadBakedFile();
		if( data == null )
			return;
		if( data.getString(0,4) != "BAKE" )
			throw "Invalid bake file";
		var count = data.getInt32(4);
		var pos = 8;
		for( i in 0...count ) {
			var len = data.getUInt16(pos);
			pos += 2;
			var name = data.getString(pos, len);
			pos += len;
			var bytesPos = data.getInt32(pos);
			pos += 4;
			var bytesLen = data.getInt32(pos);
			pos += 4;
			bakedData.set(name,data.sub(bytesPos,bytesLen));
			if( data.get(bytesPos+bytesLen) != 0xFE )
				throw "Corrupted bake file";
		}
	}

	public function getObjects<T:h3d.scene.Object>( p : Prefab, c: Class<T> ) : Array<T> {
		var root = p.to(Object3D)?.local3d;
		if(root == null) return [];
		var childObjs = getChildrenRoots(root, p, []);
		var ret = [];
		function rec(o : h3d.scene.Object) {
			var m = Std.downcast(o, c);
			if(m != null) {
				if(ret.contains(m))
					throw "?!";
				ret.push(m);
			}
			for( child in o )
				if( childObjs.indexOf(child) < 0 )
					rec(child);
		}
		rec(root);
		return ret;
	}

	function getChildrenRoots( base : h3d.scene.Object, p : Prefab, out : Array<h3d.scene.Object> ) {
		for( c in p.children ) {
			var o3d = c.to(Object3D);
			if (o3d == null)
				return out;
			if( o3d.local3d == base )
				getChildrenRoots(base, c, out);
			else
				out.push(o3d.local3d);
		}
		return out;
	}
}