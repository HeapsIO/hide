package hide.prefab;
import hide.prefab.fx.FXScene.Value;
import hide.prefab.fx.FXScene.Evaluator;

typedef ShaderParam = {
	def: hxsl.Ast.TVar,
	value: Value
};

typedef ShaderParams = Array<ShaderParam>;

class ShaderAnimation extends Evaluator {
	public var params : ShaderParams;
	public var shader : hxsl.DynamicShader;

	public function setTime(time: Float) {
		for(param in params) {
			var v = param.def;
			switch(v.type) {
				case TFloat:
					var val = getFloat(param.value, time);
					shader.setParamValue(v, val);
				case TInt:
					var val = hxd.Math.round(getFloat(param.value, time));
					shader.setParamValue(v, val);
				case TBool:
					var val = getFloat(param.value, time) >= 0.5;
					shader.setParamValue(v, val);
				case TVec(_, VFloat):
					var val = getVector(param.value, time);
					shader.setParamValue(v, val);
				default:
			}
		}
	}
}

class Shader extends Prefab {

	public var shaderDef : Context.ShaderDef;

	public function new(?parent) {
		super(parent);
		props = {};
	}
	
	override function load(o:Dynamic) {

	}

	override function save() {
		fixSourcePath();
		return {
		};
	}

	function applyVars(ctx: Context) {
		var shader = Std.instance(ctx.custom, ShaderAnimation);
		if(shader == null || shaderDef == null)
			return;
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
				case TVec(_, VFloat):
					val = h3d.Vector.fromArray(val);
				case TSampler2D:
					if(val != null)
						val = ctx.loadTexture(val);
				default:
			}
			if(val == null)
				continue;
			shader.shader.setParamValue(v, val);
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
		var anim: ShaderAnimation = new ShaderAnimation(new hxd.Rand(0));
		anim.params = makeParams();
		anim.shader = shader;
		ctx.custom = anim;
		if(shader != null) {
			for(m in ctx.local3d.getMaterials()) {
				m.mainPass.addShader(shader);
			}
		}
		applyVars(ctx);
		#end
		return ctx;
	}

	function fixSourcePath() {
		var ide = hide.Ide.inst;
		var shadersPath = ide.projectDir + "/src";  // TODO: serach in haxe.classPath?

		var path = source.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), shadersPath.toLowerCase()+"/") ) {
			path = path.substr(shadersPath.length + 1);
		}
		source = path;
	}

	function loadShaderDef(ctx: Context) {
		#if editor
		if(shaderDef == null) {
			fixSourcePath();
			var path = haxe.io.Path.withoutExtension(haxe.io.Path.withoutExtension(source));
			shaderDef = ctx.loadShader(path);
		}
		if(shaderDef == null)
			return;

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

	override function edit( ctx : EditContext ) {
		#if editor		
		super.edit(ctx);

		loadShaderDef(ctx.rootContext);
		if(shaderDef == null)
			return;

		var group = new hide.Element('<div class="group" name="Shader"></div>');

		var props = [];
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var prop = hide.tools.TypesCache.makeShaderType(v);
			props.push({name: v.name, t: prop});
		}
		group.append(hide.comp.PropsEditor.makePropsList(props));
		
		ctx.properties.add(group,this.props, function(pname) {
			ctx.onChange(this, pname);
			var inst = ctx.getContext(this);
			applyVars(inst);
		});
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

	public function makeParams() {
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = [];

		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;

			var prop = Reflect.field(props, v.name);
			if(prop == null) 
				prop = getDefault(v.type);

			var curves = hide.prefab.Curve.getCurves(this, v.name);
			if(curves == null || curves.length == 0)
				continue;

			switch(v.type) {
				case TVec(_, VFloat) :
					var isColor = v.name.toLowerCase().indexOf("color") >= 0;
					var val = isColor ? hide.prefab.Curve.getColorValue(curves) : hide.prefab.Curve.getVectorValue(curves);
					ret.push({
						def: v,
						value: val
					});

				default:
					var base = 1.0;
					if(Std.is(prop, Float) || Std.is(prop, Int))
						base = cast prop;
					var curve = getOpt(hide.prefab.Curve, v.name);
					var val = VConst(base);
					if(curve != null)
						val = VCurveValue(curve, base);
					ret.push({
						def: v,
						value: val
					});
			}
		}

		return ret;
	}

	override function getHideProps() {
		return { icon : "cog", name : "Shader", fileSource : ["hx"] };
	}

	static var _ = Library.register("shader", Shader);
}