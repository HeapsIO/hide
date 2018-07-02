package hide.prefab;

class Shader extends Prefab {

	public var shaderDef : Context.ShaderDef;

	public function new(?parent) {
		super(parent);
		type = "shader";
		props = {};
	}
	
	override function load(o:Dynamic) {

	}

	override function save() {
		fixSourcePath();
		return {
		};
	}

	override function updateInstance(ctx: Context, ?propName) {
		var shader = Std.instance(ctx.custom, hxsl.DynamicShader);
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
			shader.setParamValue(v, val);
		}
	}

	override function makeInstance(ctx:Context):Context {
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
			var defVal = evalConst(v.e);
			shader.hscriptSet(v.v.name, defVal);
		}
		for(m in ctx.local3d.getMaterials()) {
			m.mainPass.addShader(shader);
		}
		ctx.custom = shader;
		updateInstance(ctx);
		return ctx;
	}

	function fixSourcePath() {
		#if editor
		var ide = hide.Ide.inst;
		var shadersPath = ide.projectDir + "/src";  // TODO: serach in haxe.classPath?

		var path = source.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), shadersPath.toLowerCase()+"/") ) {
			path = path.substr(shadersPath.length + 1);
		}
		source = path;
		#end
	}

	public function loadShaderDef(ctx: Context) {
		if(shaderDef == null) {
			fixSourcePath();
			var path = source;
			if(StringTools.endsWith(path, ".hx")) {
				path = path.substr(0, -3);
			}
			shaderDef = ctx.loadShader(path);
		}
		if(shaderDef == null)
			return;

		#if editor
		// TODO: Where to init prefab default values?
		for( v in shaderDef.inits ) {
			if(!Reflect.hasField(props, v.v.name)) {
				var defVal = evalConst(v.e);
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
		});
		#end
	}

	public static function evalConst( e : hxsl.Ast.TExpr ) : Dynamic {
		return switch( e.e ) {
		case TConst(c):
			switch( c ) {
			case CNull: null;
			case CBool(b): b;
			case CInt(i): i;
			case CFloat(f): f;
			case CString(s): s;
			}
		case TCall({ e : TGlobal(Vec2 | Vec3 | Vec4) }, args):
			var vals = [for( a in args ) evalConst(a)];
			if( vals.length == 1 )
				switch( e.t ) {
				case TVec(n, _):
					for( i in 0...n - 1 ) vals.push(vals[0]);
					return vals;
				default:
					throw "assert";
				}
			return vals;
		default:
			throw "Unhandled constant init " + hxsl.Printer.toString(e);
		}
	}

	public static function getDefault(type: hxsl.Ast.Type): Dynamic {
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

	override function getHideProps() {
		return { icon : "cog", name : "Shader", fileSource : ["hx"] };
	}

	static var _ = Library.register("shader", Shader);
}