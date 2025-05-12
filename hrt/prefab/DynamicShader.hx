package hrt.prefab;

class DynamicShader extends Shader {

	@:c var shaderDef : {> hrt.prefab.Cache.ShaderDef, ?sclass : Class<hxsl.Shader>, ?isShaderGraph : Bool } = { shader : null, inits : null };
	@:s var isInstance : Bool = false;

	public function new(parent,  shared: ContextShared) {
		super(parent, shared);
	}

	override function setShaderParam(shader:hxsl.Shader, v:hxsl.Ast.TVar, value:Dynamic) {
		if( isInstance && !shaderDef.isShaderGraph ) {
			super.setShaderParam(shader,v,value);
			return;
		}
		cast(shader,hxsl.DynamicShader).setParamValue(v, value);
	}

	override function getShaderDefinition():hxsl.SharedShader {
		if( shaderDef.shader == null)
			loadShaderDef();
		return shaderDef.shader;
	}

	override function makeShader() {
		if( getShaderDefinition() == null )
			return null;
		if( isInstance && !shaderDef.isShaderGraph )
			shader = Type.createInstance(shaderDef.sclass,[]);
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

	override function save() : Dynamic {
		var obj = super.save();

		// Cleanup props from removed variables
		// only for shaderGraph for the moment
		// only in editor because hl has some quircks with dynamic vars
		#if editor
		if (shaderDef != null && shaderDef.shader != null && shaderDef.isShaderGraph) {
			var newProps = {};
			for (v in shaderDef.shader.data.vars) {
				if (Reflect.hasField(obj.props, v.name)) {
					Reflect.setField(newProps, v.name, Reflect.field(obj.props, v.name));
				}
			}
			if (Reflect.fields(newProps).length > 0) {
				obj.props = newProps;
			} else {
				Reflect.deleteField(obj, props);
			}
		}
		#end
		return obj;
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
		if(shaderDef.shader == null) {
			fixSourcePath();
			if (StringTools.endsWith(source, ".shgraph")) {
				shaderDef.isShaderGraph = true;
				var res = hxd.res.Loader.currentInstance.load(source);
				var shgraph = Std.downcast(res.toPrefab().load(), hrt.shgraph.ShaderGraph);
				if (shgraph == null)
					return;
				var sh = shgraph.compile(null);
				shaderDef.shader = sh.shader;
				shaderDef.inits = sh.inits;
				#if !editor
				res.watch( function() {
					@:privateAccess hxd.res.Loader.currentInstance.cache.remove(source);
				});
				#end
			}
			else if( isInstance && !shaderDef.isShaderGraph ) {
				shaderDef.sclass = loadShaderClass();
				var shared : hxsl.SharedShader = (shaderDef.sclass:Dynamic)._SHADER;
				if( shared == null ) {
					@:privateAccess Type.createEmptyInstance(shaderDef.sclass).initialize();
					shared = (shaderDef.sclass:Dynamic)._SHADER;
				}
				shaderDef.shader = shared;
				shaderDef.inits = [];
			} else {
				var path = source;
				if(StringTools.endsWith(path, ".hx")) path = path.substr(0, -3);
				var sh = shared.loadShader(path);
				shaderDef.shader = sh.shader;
				shaderDef.inits = sh.inits;
			}
		}
		if(shaderDef.shader == null)
			return;

		var forceInit = #if editor true #else false #end;
		if (forceInit || shaderDef.isShaderGraph) {
			// TODO: Where to init prefab default values?
			for( v in shaderDef.inits ) {
				if(!Reflect.hasField(props, v.variable.name)) {
					var value = v.value;
					#if editor
					// deep copy gradients
					value = haxe.Json.parse(hide.Ide.inst.toJSON(value));
					#end
					Reflect.setField(props, v.variable.name, value);
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

			if (StringTools.endsWith(source, ".shgraph")) {
				var res = hxd.res.Loader.currentInstance.load(source);
				var shgraph = Std.downcast(res.toPrefab().load(), hrt.shgraph.ShaderGraph);
				if (shgraph == null) {
					element.append(new hide.Element('<p>The given shadergraph is corrupted</p>'));
				}

				var field : hide.comp.PropsEditor.PropsField = cast (element.find("[field=source]")[0]:Dynamic).propsField;
				@:privateAccess field.fselect.onView = () -> {
					var path = field.fselect.getFullPath();
					hide.Ide.inst.openFile(path, null, (v) -> {
						var sheditor : hide.view.shadereditor.ShaderEditor = cast v;
						var renderProps = shared.editor.renderPropsRoot?.source;
						sheditor.setPrefabAndRenderDelayed(shared.currentPath,renderProps);
					});
				}
			}




		}

		super.edit(ectx);

		if( (isInstance && !shaderDef.isShaderGraph) || loadShaderClass(true) != null ) {
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