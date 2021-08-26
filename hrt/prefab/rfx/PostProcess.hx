package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
import hrt.prefab.Library;
import hxd.Math;
class PostProcess extends RendererFX {

	var shaderPass = new h3d.pass.ScreenFx(new h3d.scene.pbr.Renderer.DepthCopy());
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var shaderDef : hrt.prefab.ContextShared.ShaderDef;
	var shader : hxsl.DynamicShader;
	@:s var blendMode : h3d.mat.BlendMode = Alpha;

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( step == AfterTonemapping ) {
			r.mark("PostProcess");
			//var ctx = r.ctx;
			shaderPass.pass.setBlendMode(blendMode);
			if (shader != null)
				shaderPass.render();
		}
	}

	override function load( obj : Dynamic ) {
		loadSerializedFields(obj);
	}

	public function loadShaderDef() {
		shaderDef = shaderGraph.compile();
		if(shaderDef == null)
			return;

		#if editor
		for( v in shaderDef.inits ) {
			if(!Reflect.hasField(props, v.variable.name)) {
				Reflect.setField(props, v.variable.name, v.value);
			}
		}
		#end
	}

	function getShaderDefinition():hxsl.SharedShader {
		if( shaderDef == null )
			loadShaderDef();
		return shaderDef == null ? null : shaderDef.shader;
	}

	function setShaderParam(shader:hxsl.Shader, v:hxsl.Ast.TVar, value:Dynamic) {
		cast(shader,hxsl.DynamicShader).setParamValue(v, value);
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

	function makeShader() {
		if( getShaderDefinition() == null )
			return null;
		var shader;
		var dshader = new hxsl.DynamicShader(shaderDef.shader);
		for( v in shaderDef.inits ) {
			#if !hscript
			throw "hscript required";
			#else
			dshader.hscriptSet(v.variable.name, v.value);
			#end
		}
		shader = dshader;
		syncShaderVars(shader, shaderDef.shader);
		return shader;
	}

	override function makeInstance(ctx: Context) : Context {
		ctx = super.makeInstance(ctx);
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return;
		if (shader == null)
			shader = makeShader();
		else
			syncShaderVars(shader, shaderDef.shader);
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

		ectx.properties.add(element, this, function(pname) {
			ectx.onChange(this, pname);
			if(pname == "source") {
				shaderGraph = null;
				shaderPass.removeShader(shader);
				shader = null;
				if (shaderDef != null) {
					for(v in shaderDef.inits) {
						if (Reflect.hasField(props, v.variable.name))
							Reflect.deleteField(props, v.variable.name);
					}
					shaderDef = null;
				}

				updateProps();
				ectx.properties.clear();
				edit(ectx);
			}
		});


		super.edit(ectx);
		if (shaderGraph == null)
			return;
		var shaderDef = getShaderDefinition();

		var group = new hide.Element('<div class="group" name="Shader"></div>');
		var props = [];
		for(v in shaderDef.data.vars) {
			if( v.kind != Param )
				continue;
			if( v.qualifiers != null && v.qualifiers.indexOf(Ignore) >= 0 )
				continue;
			var prop = makeShaderParam(v);
			if( prop == null ) continue;
			props.push({name: v.name, t: prop, def: Reflect.field(props, v.name)});
		}
		group.append(hide.comp.PropsEditor.makePropsList(props));
		ectx.properties.add(group, props, function(pname) {
			ectx.onChange(this, pname);
			updateInstance(ectx.rootContext, pname);

		});

		var blendModeElt = new hide.Element('<dl><dt>Blend mode</dt><dd><select field="blendMode"></select></dd></dl>');
		ectx.properties.add(blendModeElt, this, function (pname) {
			ectx.onChange(this, pname);
			updateInstance(ectx.rootContext, pname);
		});
		var btn = new hide.Element("<input type='submit' style='width: 100%; margin-top: 10px;' value='Open Shader Graph' />");
		btn.on("click", function() {
 			ectx.ide.openFile(source);
		});

		ectx.properties.add(btn, this, function(pname) {
			ectx.onChange(this, pname);
		});
	}
	#end

	// public static function getDefault(type: hxsl.Ast.Type): Dynamic {
	// 	switch(type) {
	// 		case TBool:
	// 			return false;
	// 		case TInt:
	// 			return 0;
	// 		case TFloat:
	// 			return 0.0;
	// 		case TVec( size, VFloat ):
	// 			return [for(i in 0...size) 0];
	// 		default:
	// 			return null;
	// 	}
	// 	return null;
	// }

	static var _ = Library.register("rfx.PostProcess", PostProcess);

}