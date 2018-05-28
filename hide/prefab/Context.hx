package hide.prefab;

typedef ShaderDef = {
	var shader : hxsl.SharedShader;
	var inits : Array<{ v : hxsl.Ast.TVar, e : hxsl.Ast.TExpr }>;
}

class ContextShared {
	public var root2d : h2d.Sprite;
	public var root3d : h3d.scene.Object;
	public var contexts : Map<Prefab,Context>;
	public var cleanups : Array<Void->Void>;
	var cache : h3d.prim.ModelCache;

	public function new() {
		root2d = new h2d.Sprite();
		root3d = new h3d.scene.Object();
		contexts = new Map();
		cache = new h3d.prim.ModelCache();
		cleanups = [];
	}

	public function elements() {
		return [for(e in contexts.keys()) e];
	}

}

class Context {

	public var local2d : h2d.Sprite;
	public var local3d : h3d.scene.Object;
	public var shared : ContextShared;
	public var custom : Dynamic;

	public function new() {
	}

	public function init() {
		if( shared == null )
			shared = new ContextShared();
		local2d = shared.root2d;
		local3d = shared.root3d;
	}

	public function clone( p : Prefab ) {
		var c = new Context();
		c.shared = shared;
		c.local2d = local2d;
		c.local3d = local3d;
		c.custom = custom;
		if( p != null ) shared.contexts.set(p, c);
		return c;
	}

	public dynamic function onError( e : Dynamic ) {
		#if editor
		js.Browser.window.alert(e);
		#else
		throw e;
		#end
	}

	public function loadModel( path : String ) {
		#if editor
		return hide.comp.Scene.getCurrent().loadModel(path);
		#else
		return @:privateAccess shared.cache.loadModel(hxd.res.Loader.currentInstance.load(path).toModel());
		#end
	}

	public function loadAnimation( path : String ) {
		#if editor
		return hide.comp.Scene.getCurrent().loadAnimation(path);
		#else
		return @:privateAccess shared.cache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
		#end
	}

	public function loadTexture( path : String ) {
		#if editor
		return hide.comp.Scene.getCurrent().loadTexture("",path);
		#else
		return @:privateAccess shared.cache.loadTexture(null, path);
		#end
	}

	public function loadShader( name : String ) : ShaderDef {
		#if editor
		return hide.Ide.inst.shaderLoader.loadSharedShader(name);
		#else
		return null;
		#end
	}
	public function locateObject( path : String ) {
		if( path == null )
			return null;
		var parts = path.split(".");
		var root = shared.root3d;
		while( parts.length > 0 ) {
			var v = null;
			var pname = parts.shift();
			for( o in root )
				if( o.name == pname ) {
					v = o;
					break;
				}
			if( v == null ) {
				v = root.getObjectByName(pname);
				if( v != null && v.parent != root ) v = null;
			}
			if( v == null ) {
				var parts2 = path.split(".");
				for( i in 0...parts.length ) parts2.pop();
				onError("Object not found " + parts2.join("."));
				return null;
			}
			root = v;
		}
		return root;
	}

}
