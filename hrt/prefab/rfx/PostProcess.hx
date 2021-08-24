package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
import hrt.prefab.Library;
import hxd.Math;

@:enum private abstract AccessKind(Int) {
	var Dynamic = 0;
	var Float = 1;
	var Structure = 2;
}

private class Access {
	public var kind : AccessKind;
	public var index : Int;
	public var fields : Array<String>;
	public function new(kind,index,fields) {
		this.kind = kind;
		this.index = index;
		this.fields = fields;
	}
}

class DynamicScreenShader extends h3d.shader.ScreenShader {
	var values = new Array<Dynamic>();
	var floats = new Array<Float>();
	var accesses = new Array<Access>();
	var varIndexes = new Map<Int,Int>();
	var varNames = new Map<String,Int>();

	public function new( s : hxsl.SharedShader ) {
		this.shader = s;
		super();
		for( v in s.data.vars )
			addVarIndex(v);
	}

	function addVarIndex(v:hxsl.Ast.TVar, ?access : Access, ?defObj : Dynamic ) {
		if( v.kind != Param )
			return;
		var isFloat = v.type == TFloat && access == null;
		var vid = isFloat ? floats.length : values.length;
		if( access != null )
			access = new Access(Structure, access.index, access.fields.copy());
		switch(v.type){
		case TStruct(vl):
			var vobj = {};
			if( access == null ) {
				values.push(vobj);
				access = new Access(Structure,vid,[]);
				varNames.set(v.name, vid);
			} else {
				Reflect.setField(defObj, v.name, vobj);
			}
			for( v in vl ) {
				access.fields.push(v.name);
				addVarIndex(v, access, vobj);
				access.fields.pop();
			}
			return;
		default:
		}
		var value : Dynamic = null;
		switch( v.type ) {
		case TVec(_):
			value = new h3d.Vector();
		case TMat3, TMat4, TMat3x4:
			var m = new h3d.Matrix();
			m.identity();
			value = m;
		case TInt, TFloat:
			value = 0;
		case TBool:
			value = false;
		default:
		}
		if( access == null ) {
			if( isFloat ) {
				varNames.set(v.name, -vid-1);
				floats.push(0);
			} else {
				varNames.set(v.name, vid);
				values.push(value);
			}
		} else
			Reflect.setField(defObj, v.name, value);

		var vidx = accesses.length;
		varIndexes.set(v.id, vidx);
		accesses.push(access == null ? new Access(isFloat?Float:Dynamic,vid,null) : access);
	}

	override function getParamValue(index:Int) : Dynamic {
		var a = accesses[index];
		switch( a.kind ) {
		case Dynamic:
			return values[a.index];
		case Float:
			return floats[a.index];
		case Structure:
			var v : Dynamic = values[a.index];
			for( f in a.fields )
				v = Reflect.field(v, f);
			return v;
		}
	}

	override function getParamFloatValue(index:Int):Float {
		var a = accesses[index];
		if( a.kind != Float )
			return getParamValue(index);
		return floats[a.index];
	}

	public function setParamValue( p : hxsl.Ast.TVar, value : Dynamic ) {
		var vidx = varIndexes.get(p.id);
		var a = accesses[vidx];
		switch( a.kind ) {
		case Dynamic:
			values[a.index] = value;
		case Float:
			floats[a.index] = value;
		case Structure:
			var obj = values[a.index];
			for( i in 0...a.fields.length - 1 )
				obj = Reflect.field(obj, a.fields[i]);
			Reflect.setField(obj, a.fields[a.fields.length - 1], value);
		}
	}

	public function setParamFloatValue( p : hxsl.Ast.TVar, value : Float ) {
		var vidx = varIndexes.get(p.id);
		var a = accesses[vidx];
		if( a.kind != Float ) {
			setParamValue(p, value);
			return;
		}
		floats[a.index] = value;
	}

	override function updateConstants( globals : hxsl.Globals ) {
		constBits = 0;
		var c = shader.consts;
		while( c != null ) {
			if( c.globalId != 0 ) {
				c = c.next;
				continue;
			}
			var v : Dynamic = getParamValue(varIndexes.get(c.v.id));
			switch( c.v.type ) {
			case TInt:
				var v : Int = v;
				if( v >>> c.bits != 0 ) throw "Constant outside range";
				constBits |= v << c.pos;
			case TBool:
				if( v ) constBits |= 1 << c.pos;
			case TChannel(n):
				throw "TODO:"+c.v.type;
			default:
				throw "assert";
			}
			c = c.next;
		}
		updateConstantsFinal(globals);
	}


	#if hscript
	@:keep public function hscriptGet( field : String ) : Dynamic {
		var vid = varNames.get(field);
		if( vid == null )
			return Reflect.getProperty(this, field);
		if( vid < 0 )
			return floats[-vid-1];
		return values[vid];
	}

	@:keep public function hscriptSet( field : String, value : Dynamic ) : Dynamic {
		var vid = varNames.get(field);
		if( vid == null ) {
			Reflect.setProperty(this, field, value);
			return value;
		}
		if( vid < 0 )
			floats[-vid-1] = value;
		else
			values[vid] = value;
		return value;
	}
	#end

	override function toString() {
		return "DynamicScreenShader<" + shader.data.name+">";
	}

}

class PostProcess extends RendererFX {

	var shaderPass : h3d.pass.ScreenFx<DynamicScreenShader>;
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var shaderDef : hrt.prefab.ContextShared.ShaderDef;
	var shader : DynamicScreenShader;

	function sync( r : h3d.scene.Renderer ) {
		var ctx = r.ctx;
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( step == AfterTonemapping ) {
			r.mark("PostProcess");
			sync(r);
			if (shader != null)
				shaderPass.render();
		}
	}

	// function fixSourcePath() {
	// 	#if editor
	// 	// shader source is loaded with ../src/path/to/Shader.hx
	// 	// but we want the path relative to source path path/to/Shader.hx only
	// 	var ide = hide.Ide.inst;
	// 	var shadersPath = ide.projectDir + "/src";  // TODO: serach in haxe.classPath?

	// 	var path = ide.getPath(source);
	// 	var fpath = sys.FileSystem.fullPath(path);
	// 	if( fpath != null ) path = fpath;
	// 	path = path.split("\\").join("/");
	// 	if( StringTools.startsWith(path.toLowerCase(), shadersPath.toLowerCase()+"/") ) {
	// 		path = path.substr(shadersPath.length + 1);
	// 		source = path;
	// 	}
	// 	#end
	// }

	// function loadShaderClass(opt=false) : Class<hxsl.Shader> {
	// 	var path = source;
	// 	if(StringTools.endsWith(path, ".hx")) path = path.substr(0, -3);
	// 	var cpath = path.split("/").join(".");
	// 	var cl = cast Type.resolveClass(cpath);
	// 	if( cl == null && !opt ) throw "Missing shader class"+cpath;
	// 	return cl;
	// }

	public function loadShaderDef(ctx: Context) {
		// if(shaderDef == null) {
			// fixSourcePath();
			// shaderClass = loadShaderClass();
			// var shared : hxsl.SharedShader = (shaderClass:Dynamic)._SHADER;
			// if( shared == null ) {
			// 	@:privateAccess Type.createEmptyInstance(shaderClass).initialize();
			// 	shared = (shaderClass:Dynamic)._SHADER;
			// }
			// shaderDef = { shader : shared, inits : [] };
			// if( isInstance ) {
			// 	shaderClass = loadShaderClass();
			// 	var shared : hxsl.SharedShader = (shaderClass:Dynamic)._SHADER;
			// 	if( shared == null ) {
			// 		@:privateAccess Type.createEmptyInstance(shaderClass).initialize();
			// 		shared = (shaderClass:Dynamic)._SHADER;
			// 	}
			// 	shaderDef = { shader : shared, inits : [] };
			// } else {
			// 	var path = source;
			// 	if(StringTools.endsWith(path, ".hx")) path = path.substr(0, -3);
			// 	shaderDef = ctx.loadShader(path);
			// }
		// }
		shaderDef = shaderGraph.compile();
		if(shaderDef == null)
			return;

		#if editor
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
		#end
	}

	function getShaderDefinition(ctx:Context):hxsl.SharedShader {
		if( shaderDef == null && ctx != null )
			loadShaderDef(ctx);
		return shaderDef == null ? null : shaderDef.shader;
	}

	function setShaderParam(shader:hxsl.Shader, v:hxsl.Ast.TVar, value:Dynamic) {
		Reflect.setProperty(shader, v.name, value);
		// if( isInstance ) {
		// 	Reflect.setProperty(shader, v.name, value);
		// 	return;
		// }
		//cast(shader,hxsl.DynamicShader).setParamValue(v, value);
	}

	function syncShaderVars( shader : hxsl.Shader, shaderDef : hxsl.SharedShader ) {
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
			case TVec(_, VFloat):
				if(val != null) {
					if( Std.is(val,Int) ) {
						var v = new h3d.Vector();
						v.setColor(val);
						val = v;
					} else
						val = h3d.Vector.fromArray(val);
				} else
					val = new h3d.Vector();
			case TSampler2D:
				if( val != null )
					val = hxd.res.Loader.currentInstance.load(val).toTexture();
				else {
					var childNoise = getOpt(hrt.prefab.l2d.NoiseGenerator, v.name);
					if(childNoise != null)
						val = childNoise.toTexture();
				}
			default:
			}
			if(val == null)
				continue;
			setShaderParam(shader,v,val);
		}
	}

	function makeShader( ?ctx:Context ) {
		if( getShaderDefinition(ctx) == null )
			return null;
		var shader;
		var dshader = new DynamicScreenShader(shaderDef.shader);
		for( v in shaderDef.inits ) {
			#if !hscript
			throw "hscript required";
			#else
			dshader.hscriptSet(v.variable.name, v.value);
			#end
		}
		shader = dshader;
		//shader = Type.createInstance(shaderClass,[]);
		// if( isInstance )
		// 	shader = Type.createInstance(shaderClass,[]);
		// else {
			// var dshader = new hxsl.DynamicShader(shaderDef.shader);
			// for( v in shaderDef.inits ) {
			// 	#if !hscript
			// 	throw "hscript required";
			// 	#else
			// 	dshader.hscriptSet(v.variable.name, v.value);
			// 	#end
			// }
			// shader = dshader;
		// }
		syncShaderVars(shader, shaderDef.shader);
		return shader;
	}

	override function makeInstance(ctx: Context) : Context {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return ctx;

		ctx = super.makeInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return;

		shader = makeShader(ctx);
		shaderPass = new h3d.pass.ScreenFx(shader);
		shaderPass.addShader(shader);
	}

	public function resolveRef(shared : hrt.prefab.ContextShared) {
		if(shaderGraph != null)
			return shaderGraph;
		if(source == null)
			return null;

		#if editor
		shaderGraph = new hrt.shgraph.ShaderGraph(source);
		#else
		return null;
		#end
		return shaderGraph;
	}

	function makeShaderParam( v : hxsl.Ast.TVar ) : hrt.prefab.Props.PropType {
		var min : Null<Float> = null, max : Null<Float> = null;
		if( v.qualifiers != null )
			for( q in v.qualifiers )
				switch( q ) {
				case Range(rmin, rmax): min = rmin; max = rmax;
				default:
				}
		return switch( v.type ) {
		case TInt:
			PInt(min == null ? null : Std.int(min), max == null ? null : Std.int(max));
		case TFloat:
			PFloat(min != null ? min : 0.0, max != null ? max : 1.0);
		case TBool:
			PBool;
		case TSampler2D:
			PTexture;
		case TVec(n, VFloat):
			PVec(n);
		default:
			PUnsupported(hxsl.Ast.Tools.toString(v.type));
		}
	}

	#if editor
	override function edit( ectx : hide.prefab.EditContext ) {
		var element = new hide.Element('
			<div class="group" name="Reference">
			<dl>
				<dt>Reference</dt><dd><input type="fileselect" extensions="hlshader" field="source"/></dd>
			</dl>
			</div>');

		function updateProps() {
			var input = element.find("input");
			updateInstance(ectx.rootContext);
			var found = shaderGraph != null;
			input.toggleClass("error", !found);
		}
		updateProps();

		var props = ectx.properties.add(element, this, function(pname) {
			ectx.onChange(this, pname);
			if(pname == "source") {
				shaderGraph = null;
				updateProps();
				ectx.properties.clear();
				edit(ectx);
			}
		});


		super.edit(ectx);
		var ctx = ectx.getContext(this);
		if (shaderGraph == null)
			return;
		var shaderDef = getShaderDefinition(ctx);
		if( shaderDef == null || ctx == null )
			return;

		var group = new hide.Element('<div class="group" name="Shader"></div>');
		var props = [];
		for(v in shaderDef.data.vars) {
			if( v.kind != Param )
				continue;
			if( v.qualifiers != null && v.qualifiers.indexOf(Ignore) >= 0 )
				continue;
			var prop = makeShaderParam(v);
			if( prop == null ) continue;
			props.push({name: v.name, t: prop});
		}
		group.append(hide.comp.PropsEditor.makePropsList(props));
		ectx.properties.add(group,this.props, function(pname) {
			ectx.onChange(this, pname);

		});

		var btn = new hide.Element("<input type='submit' style='width: 100%; margin-top: 10px;' value='Open Shader Graph' />");
		btn.on("click", function() {
 			ectx.ide.openFile(source);
		});

		ectx.properties.add(btn,this.props, function(pname) {
			ectx.onChange(this, pname);
		});
	}
	#end

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

	static var _ = Library.register("rfx.PostProcess", PostProcess);

}