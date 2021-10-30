package hrt.prefab;

typedef ShaderDef = {
	var shader : hxsl.SharedShader;
	var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }>;
}

typedef ShaderDefCache = Map<String, ShaderDef>;

class ContextShared {
	public var root2d : h2d.Object;
	public var root3d : h3d.scene.Object;
	public var contexts : Map<Prefab,Context>;
	public var currentPath : String;
	public var editorDisplay : Bool;

	/**
		When make() is called on prefab, it will instead call customMake on
		each child with current which can either intercept or call make() recursively.
	 **/
	public var customMake : Context -> Prefab -> Void;

	/**
		If is a reference to another prefab file, this is the parent prefab.
		See refContexts for children.
	**/
	public var parent : { prefab : Prefab, shared : ContextShared };

	var cache : h3d.prim.ModelCache;
	var shaderCache : ShaderDefCache;
	var bakedData : Map<String, haxe.io.Bytes>;
	/**
		References to prefab within the same scene
	**/
	var sceneReferences : Map<Prefab,Array<Context>>;
	/**
		Contexts of references to other prefabs
	**/
	var refsContexts : Map<Prefab, ContextShared>;

	public function new( ?res : hxd.res.Resource ) {
		root2d = new h2d.Object();
		root3d = new h3d.scene.Object();
		contexts = new Map();
		cache = new h3d.prim.ModelCache();
		shaderCache = new ShaderDefCache();
		sceneReferences = new Map();
		refsContexts = new Map();
		if( res != null ) currentPath = res.entry.path;
	}

	public function onError( e : Dynamic ) {
		throw e;
	}

	public function elements() {
		return [for(e in contexts.keys()) e];
	}

	public function getContexts(p: Prefab) : Array<Context> {
		var ret : Array<Context> = [];
		var ctx = contexts.get(p);
		if(ctx != null)
			ret.push(ctx);
		var ctxs = sceneReferences.get(p);
		if( ctxs != null )
			for( v in ctxs )
				ret.push(v);
		for( ref in refsContexts )
			for( v in ref.getContexts(p) )
				ret.push(v);
		return ret;
	}

	public function find<T:hrt.prefab.Prefab>( cur : Prefab, cl : Class<T>, ?name, ?references ) : T {
		var root = cur;
		while( root.parent != null ) root = root.parent;
		var p = root.getOpt(cl, name, true);
		if( p != null )
			return p;
		if( references ) {
			for( p => ref in refsContexts ) {
				var v = ref.find(p, cl, name, true);
				if( v != null ) return v;
			}
		}
		return null;
	}

	public function getRef( prefab : Prefab ) {
		return refsContexts.get(prefab);
	}

	public function cloneRef( prefab : Prefab, newPath : String ) {
		var ctx = contexts.get(prefab);
		if( ctx == null )
			throw "Prefab reference has no context created";
		var sh = refsContexts.get(prefab);
		if( sh != null ) {
			sh.root2d = ctx.local2d;
			sh.root3d = ctx.local3d;
			return sh;
		}
		sh = allocForRef();
		refsContexts.set(prefab, sh);

		sh.root2d = ctx.local2d;
		sh.root3d = ctx.local3d;
		// own contexts
		// own references
		sh.currentPath = newPath;
		sh.editorDisplay = editorDisplay;
		sh.parent = { shared : this, prefab : prefab };
		sh.cache = cache;
		sh.shaderCache = shaderCache;
		sh.customMake = customMake;
		// own bakedData
		// own refsContext
		return sh;
	}

	function allocForRef() {
		return new ContextShared();
	}

	public function loadDir(p : String, ?dir : String ) : Array<hxd.res.Any> {
		var datPath = new haxe.io.Path(currentPath);
		datPath.ext = "dat";
		var path = datPath.toString() + "/" + p;
		if(dir != null) path += "/" + dir;
		return try hxd.res.Loader.currentInstance.dir(path) catch( e : hxd.res.NotFound ) null;
	}

	public function loadPrefabDat(file : String, ext : String, p : String) : hxd.res.Any {
		var datPath = new haxe.io.Path(currentPath);
		datPath.ext = "dat";
		var path = new haxe.io.Path(datPath.toString() + "/" + p + "/" + file);
		path.ext = ext;
		return try hxd.res.Loader.currentInstance.load(path.toString()) catch( e : hxd.res.NotFound ) null;
	}

	public function savePrefabDat(file : String, ext : String, p : String, bytes : haxe.io.Bytes ) {
		throw "Not implemented";
	}

	public function loadPrefab( path : String ) : Prefab {
		return hxd.res.Loader.currentInstance.load(path).toPrefab().load();
	}

	public function loadShader( path : String ) : ShaderDef {
		var r = shaderCache.get(path);
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
		shaderCache.set(path, r);
		return r;
	}

	public function loadModel( path : String ) {
		return cache.loadModel(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	public function loadAnimation( path : String ) {
		return @:privateAccess cache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	public function loadTexture( path : String ) {
		return cache.loadTexture(null, path);
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

	function getChildrenRoots( base : h3d.scene.Object, p : Prefab, out : Array<h3d.scene.Object> ) {
		for( c in p.children ) {
			var ctx = contexts.get(c);
			if( ctx == null ) continue;
			if( ctx.local3d == base )
				getChildrenRoots(base, c, out);
			else
				out.push(ctx.local3d);
		}
		return out;
	}

	public function getSelfObject( p : Prefab ) : h3d.scene.Object {
		var ctx = contexts.get(p);
		if(ctx == null) return null;

		var parentCtx = p.parent != null ? contexts.get(p.parent) : null;
		if(parentCtx != null && ctx.local3d == parentCtx.local3d)
			return null;

		return ctx.local3d;
	}

	public function getObjects<T:h3d.scene.Object>( p : Prefab, c: Class<T> ) : Array<T> {
		var root = getSelfObject(p);
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

	public function getMaterials( p : Prefab ) {
		var root = getSelfObject(p);
		if(root == null) return [];
		var childObjs = getChildrenRoots(root, p, []);
		var ret = [];
		function rec(o : h3d.scene.Object) {
			if( o.isMesh() ) {
				var m = o.toMesh();
				var multi = Std.downcast(m, h3d.scene.MultiMaterial);
				if( multi != null ) {
					for( m in multi.materials )
						if( m != null )
							ret.push(m);
				} else if( m.material != null )
					ret.push(m.material);
			}
			for( child in o )
				if( childObjs.indexOf(child) < 0 )
					rec(child);
		}
		rec(root);
		return ret;
	}

}