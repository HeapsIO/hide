package hrt.prefab2;


typedef ShaderDef = {
	var shader : hxsl.SharedShader;
	var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }>;
}

typedef ShaderDefCache = Map<String, ShaderDef>;

class Cache {
	static var inst : Cache;

	// Override this with your own cache objets
	public static dynamic function init() : Cache {
		var c = new Cache();
		c.modelCache = new h3d.prim.ModelCache();
		c.shaderDefCache = new ShaderDefCache();
		return c;
	}

	public function new() {

	}

	public static function get() : Cache {
		if (inst == null)
			inst = Cache.init();
		return inst;
	}

	public var modelCache : h3d.prim.ModelCache = new h3d.prim.ModelCache();
	public var shaderDefCache : ShaderDefCache = new ShaderDefCache();
}