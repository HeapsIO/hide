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

	public function applyVars(ctx: Context, time: Float=0.0) {
		var shader = Std.instance(ctx.custom, hxsl.DynamicShader);
		if(shader == null || shaderDef == null)
			return;
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
				case TFloat:
					val = getFloatParam(v.name, time);
				case TInt:
					val = hxd.Math.round(getFloatParam(v.name, time));
				case TBool:
					val = getFloatParam(v.name, time) >= 0.5;
				case TVec(_, VFloat):
					val = getVectorParam(v.name, time);
				case TSampler2D:
					if(val != null)
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

	// public function getCurves(prefix: String) {
	// 	return this.getAll(hide.prefab.Curve).filter(c -> c.name.split(".")[0] == prefix);
	// }

	public function getFloatParam(name: String, time: Float) {
		var ret = cast Reflect.field(props, name);
		var curve = getOpt(hide.prefab.Curve, name);
		if(curve != null)
			ret = curve.getVal(time);
		return ret;
	}

	public function getVectorParam(name: String, time: Float) : h3d.Vector {
		var ret = new h3d.Vector();
		var a = Std.instance(Reflect.field(props, name), Array);
		if(a == null)
			return ret;
		ret = h3d.Vector.fromArray(a);
		var curves = hide.prefab.Curve.getCurves(this, name);
		if(curves != null && curves.length > 0) {
			if(curves.length >= 3 && name.toLowerCase().indexOf("color") >= 0)
				ret = hide.prefab.Curve.getColorValue(curves, time);
			else {
				// TODO: Map by name instead of order?
				ret.x = curves[0].getVal(time);
				if(curves.length > 1) ret.y = curves[1].getVal(time);
				if(curves.length > 2) ret.z = curves[2].getVal(time);
				if(curves.length > 3) ret.w = curves[3].getVal(time);
			}
		}
		return ret;
	}

	override function getHideProps() {
		return { icon : "cog", name : "Shader", fileSource : ["hx"] };
	}

	static var _ = Library.register("shader", Shader);
}