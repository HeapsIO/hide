package hide.prefab;

class Shader extends Prefab {

	public var shaderDef : Context.ShaderDef;

	public function new(?parent) {
		super(parent);
		props = {};
	}
	
	override function load(o:Dynamic) {

	}

	override function save() {
		return {
		};
	}

	public function applyVars(ctx: Context) {
		var shader = Std.instance(ctx.custom, hxsl.DynamicShader);
		if(shader == null || shaderDef == null)
			return;
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
				case TVec( size, VFloat ):
					var a = Std.instance(val, Array);
					if(a == null)
						continue;
					val = h3d.Vector.fromArray(a);
				case TSampler2D:
					val = ctx.loadTexture(val);
				default:
			}
			if(val == null)
				continue;
			shader.setParamValue(v, val);
		}
	}

	override function makeInstance(ctx:Context):Context {
		#if editor
		if(source == null)
			return ctx;
		if(ctx.local3d == null)
			return ctx;
		ctx = ctx.clone(this);
		loadShaderDef(ctx);
		if(shaderDef == null)
			return ctx;
		var shader = new hxsl.DynamicShader(shaderDef.shader);
		for( v in shaderDef.inits ) {
			var defVal = hide.tools.TypesCache.evalConst(v.e);
			shader.hscriptSet(v.v.name, defVal);
		}
		ctx.custom = shader;
		if(shader != null) {
			for(m in ctx.local3d.getMaterials()) {
				m.mainPass.addShader(shader);
			}
		}
		applyVars(ctx);
		#end
		return ctx;
	}

	function loadShaderDef(ctx: Context) {
		#if editor
		if(shaderDef == null)
			shaderDef = ctx.loadShader("shaders/TestShader");

		// TODO: Where to init prefab default values?
		for( v in shaderDef.inits ) {
			if(!Reflect.hasField(props, v.v.name)) {
				var defVal = hide.tools.TypesCache.evalConst(v.e);
				Reflect.setField(props, v.v.name, defVal);
			}
		}
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			if(!Reflect.hasField(props, v.name)) {
				Reflect.setField(props, v.name, getDefault(v.type));
			}
		}
		#end
	}

	static function getDefault(type: hxsl.Ast.Type): Dynamic {
		switch(type) {
			case TBool:
				return false;
			case TInt:
				return 0;
			case TFloat:
				return 0.0;
			case TVec( size, VFloat ):
				return [for(i in 0...size) 0];
			default:
				return null;
		}
		return null;
	}

	override function edit( ctx : EditContext ) {
		#if editor		
		super.edit(ctx);

		loadShaderDef(ctx.rootContext);
		if(shaderDef == null)
			return;

		var props = [];
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var prop = hide.tools.TypesCache.makeShaderType(v);
			props.push({name: v.name, t: prop});
		}
		ctx.properties.addProps(props, this.props, function(pname) {
			ctx.onChange(this, pname);
			var inst = ctx.getContext(this);
			applyVars(inst);
		});
		#end
	}

	override function getHideProps() {
		return { icon : "cog", name : "Shader", fileSource : ["hx"] };
	}

	static var _ = Library.register("shader", Shader);
}