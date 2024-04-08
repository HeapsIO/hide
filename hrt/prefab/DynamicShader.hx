package hrt.prefab;

class DynamicShader extends Shader {

	var shaderDef : hrt.prefab.Cache.ShaderDef;
	var shaderClass : Class<hxsl.Shader>;
	@:s var isInstance : Bool = false;
	var isShadergraph : Bool = false;

	public function new(parent,  shared: ContextShared) {
		super(parent, shared);
	}

	override function copy(other:Prefab) {
		super.copy(other);
		var shaderDef = Std.downcast(other, DynamicShader)?.getShaderDefinition();
	}

	override function setShaderParam(shader:hxsl.Shader, v:hxsl.Ast.TVar, value:Dynamic) {
		if( isInstance && !isShadergraph ) {
			super.setShaderParam(shader,v,value);
			return;
		}
		cast(shader,hxsl.DynamicShader).setParamValue(v, value);
	}

	override function getShaderDefinition():hxsl.SharedShader {
		if( shaderDef == null)
			loadShaderDef();
		return shaderDef == null ? null : shaderDef.shader;
	}

	override function makeShader() {
		if( getShaderDefinition() == null )
			return null;
		if( isInstance && !isShadergraph)
			shader = Type.createInstance(shaderClass,[]);
		else {
			var dshader = new hxsl.DynamicShader(shaderDef.shader);
			for( v in shaderDef.inits ) {
				dshader.hscriptSet(v.variable.name, v.value);
			}
			shader = dshader;
		}
		syncShaderVars(shader, shaderDef.shader);
		return shader;
	}

	function fixSourcePath() {
		#if editor
		// shader source is loaded with ../src/path/to/Shader.hx
		// but we want the path relative to source path path/to/Shader.hx only
		var ide = hide.Ide.inst;
		var shadersPath = ide.projectDir + "/src";  // TODO: serach in haxe.classPath?

		var path = ide.getPath(source);
		var fpath = sys.FileSystem.fullPath(path);
		if( fpath != null ) path = fpath;
		path = path.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), shadersPath.toLowerCase()+"/") ) {
			path = path.substr(shadersPath.length + 1);
			source = path;
		}
		#end
	}

	function loadShaderClass(opt=false) : Class<hxsl.Shader> {
		var path = source;
		if(StringTools.endsWith(path, ".hx")) path = path.substr(0, -3);
		var cpath = path.split("/").join(".");
		var cl = cast Type.resolveClass(cpath);
		if( cl == null && !opt ) throw "Missing shader class "+cpath;
		return cl;
	}

	public function loadShaderDef() {
		if(shaderDef == null) {
			fixSourcePath();
			if (StringTools.endsWith(source, ".shgraph")) {
				isShadergraph = true;
				var shgraph = Std.downcast(hxd.res.Loader.currentInstance.load(source).toPrefab().load(), hrt.shgraph.ShaderGraph);
				if (shgraph == null)
					throw source + " is not a valid shadergraph";
				shaderDef = shgraph.compile3(null);
			}
			else if( isInstance && !isShadergraph ) {
				shaderClass = loadShaderClass();
				var shared : hxsl.SharedShader = (shaderClass:Dynamic)._SHADER;
				if( shared == null ) {
					@:privateAccess Type.createEmptyInstance(shaderClass).initialize();
					shared = (shaderClass:Dynamic)._SHADER;
				}
				shaderDef = { shader : shared, inits : [] };
			} else {
				var path = source;
				if(StringTools.endsWith(path, ".hx")) path = path.substr(0, -3);
				shaderDef = shared.loadShader(path);
			}
		}
		if(shaderDef == null)
			return;

		var forceInit = #if editor true #else false #end;
		if (forceInit || isShadergraph) {
			// TODO: Where to init prefab default values?
			for( v in shaderDef.inits ) {
				if(!Reflect.hasField(props, v.variable.name)) {
					Reflect.setField(props, v.variable.name, v.value);
				}
			}
			for(v in shaderDef.shader.data.vars) {
				if(v.kind != Param)
					continue;
				if(!Reflect.hasField(props, v.name)) {
					Reflect.setField(props, v.name, getDefault(v.type));
				}
			}
		}
	}

	#if editor
	override function edit( ectx : hide.prefab.EditContext ) {

		if (StringTools.endsWith(source, ".shgraph")) {
			var element = new hide.Element('
			<div class="group" name="Source">
			<dl>
				<dt>Path</dt><dd><input type="fileselect" extensions="shgraph" field="source"/></dd>
			</dl>
			</div>');

			ectx.properties.add(element, this, function(pname) {
				ectx.onChange(this, pname);
				if (pname == "source") {
					shaderDef = null;
					if(!ectx.properties.isTempChange)
						ectx.rebuildPrefab(this);
				}
			});
		}

		super.edit(ectx);

		if( (isInstance && !isShadergraph) || loadShaderClass(true) != null ) {
			ectx.properties.add(hide.comp.PropsEditor.makePropsList([{
				name : "isInstance",
				t : PBool,
			}]), this);
		}
	}
	#end

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

	static var _ = Prefab.register("shader", DynamicShader);
}