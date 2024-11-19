package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
import hxd.Math;

private class GraphShader extends h3d.shader.ScreenShader {

	static var SRC = {
		@const var USE_PREV_TARGET : Bool = false;

		@global var global : {
			var screenShaderInput : Sampler2D;
		}

		function fragment() {
			if ( USE_PREV_TARGET )
				pixelColor = global.screenShaderInput.get(calculatedUV);
		}
	}
}

enum abstract ScreenShaderGraphMode(String) {
	var BeforeTonemapping;
	var AfterTonemapping;
}
@:access(h3d.scene.Renderer)
class ScreenShaderGraph extends RendererFX {

	var shaderPass = new h3d.pass.ScreenFx(new GraphShader());
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var shaderDef : hrt.prefab.Cache.ShaderDef;
	var shader : hxsl.DynamicShader;

	@:s public var renderMode : ScreenShaderGraphMode;
	@:s public var blend : h3d.mat.PbrMaterial.PbrBlend = None;
	@:s public var usePrevTarget : Bool = false;

	function new(parent, shared: ContextShared) {
		super(parent, shared);
		renderMode = AfterTonemapping;
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		syncShaderVars();

		shaderPass.pass.setBlendMode(switch ( blend ) {
			case None: None;
			case Alpha: Alpha;
			case Add: Add;
			case AlphaAdd: AlphaAdd;
			case Multiply: Multiply;
			case AlphaMultiply: AlphaMultiply;
		});
		if( step == AfterTonemapping && renderMode == AfterTonemapping) {
			r.mark("ScreenShaderGraph");
			if (shader != null) {
				shaderPass.shader.USE_PREV_TARGET = usePrevTarget;
				if ( usePrevTarget) {
					var ctx = r.ctx;
					var target = r.allocTarget("ppTarget", false);
					r.ctx.setGlobal("global.screenShaderInput", ctx.getGlobal("ldrMap"));
					// shaderPass.shader.source = ctx.getGlobal("ldrMap");

					ctx.engine.pushTarget(target);
					shaderPass.render();
					ctx.engine.popTarget();

					ctx.setGlobal("ldrMap", target);
					r.setTarget(target);
				} else {
					shaderPass.render();
				}
			}
		}
		if( step == BeforeTonemapping && renderMode == BeforeTonemapping) {
			r.mark("ScreenShaderGraph");
			if (shader != null) {
				shaderPass.shader.USE_PREV_TARGET = usePrevTarget;
				if ( usePrevTarget ) {
					var ctx = r.ctx;
					var target = r.allocTarget("ppTarget", false, 1.0, RGBA16F);
					r.ctx.setGlobal("global.screenShaderInput", ctx.getGlobal("ldrMap"));

					ctx.engine.pushTarget(target);
					shaderPass.render();
					ctx.engine.popTarget();

					r.copy(target, ctx.getGlobal("hdrMap"));
				} else {
					shaderPass.render();
				}
			}
		}
	}

	public function loadShaderDef() {
		if (shaderGraph == null)
			resolveRef();
		shaderDef = shaderGraph.compile(null);
		if(shaderDef == null)
			return;

		#if editor
		for( v in shaderDef.inits ) {
			if (props == null)
				props = {};
			if(!Reflect.hasField(props, v.variable.name)) {
				Reflect.setField(props, v.variable.name, v.value);
			}
		}
		#end
	}

	override function makeInstance() {
		super.makeInstance();
		updateInstance();
	}

	public function getShaderDefinition(): hxsl.SharedShader {
		if( shaderDef == null )
			loadShaderDef();
		return shaderDef == null ? null : shaderDef.shader;
	}

	function setShaderParam(shader:hxsl.Shader, v:hxsl.Ast.TVar, value:Dynamic) {
		cast(shader,hxsl.DynamicShader).setParamValue(v, value);
	}

	function syncShaderVars() {
		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
			case TVec(4, VFloat):
				if(val != null) {
					if( Std.isOfType(val,Int) ) {
						var v = new h3d.Vector4();
						v.setColor(val);
						val = v;
					} else
						val = h3d.Vector4.fromArray(val);
				} else
					val = new h3d.Vector4();
			case TVec(n, VFloat):
				if(val != null) {
					if( Std.isOfType(val,Int) ) {
						var v = new h3d.Vector();
						v.setColor(val);
						val = v;
					} else
						val = h3d.Vector.fromArray(val);
				} else
					val = new h3d.Vector();
			case TSampler(_):
				if( val != null )
					val = hrt.impl.TextureType.Utils.getTextureFromValue(val);//hxd.res.Loader.currentInstance.load(val).toTexture();
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
		var dshader = new hxsl.DynamicShader(shaderDef.shader);
		for( v in shaderDef.inits )
			dshader.hscriptSet(v.variable.name, v.value);
		shader = dshader;
		syncShaderVars();
		shaderPass.addShader(shader);
		return shader;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		if (instance != null) {
			for (f in Reflect.fields(props)) {
				Reflect.setField(instance.props, f, Reflect.field(this.props, f));
			}
		}
		var p = resolveRef();
		if(p == null)
			return;
		if (shader == null)
			shader = makeShader();
		else
			syncShaderVars();
	}

	public function resolveRef() {
		if(shaderGraph != null)
			return shaderGraph;
		if(source == null)
			return null;

		shaderGraph = cast hxd.res.Loader.currentInstance.load(source).toPrefab().load();
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
		case TSampler(_):
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
			<div class="group" name="Properties">
			<dl>
				<dt>Render Mode</dt>
				<dd><select field="renderMode">
					<option value="BeforeTonemapping">Before Tonemapping</option>
					<option value="AfterTonemapping">After Tonemapping</option>
				</select></dd>
				<dt>Blend mode</dt>
				<dd>
					<select field="blend">
						<option value="None">None</option>
						<option value="Alpha">Alpha</option>
						<option value="Add">Add</option>
						<option value="AlphaAdd">AlphaAdd</option>
						<option value="Multiply">Multiply</option>
						<option value="AlphaMultiply">AlphaMultiply</option>
					</select>
				</dd>
				<dt>Reference</dt><dd><input type="fileselect" extensions="shgraph" field="source"/></dd>
				<dt>Prev target as input</dt><dd><input type="checkbox" field="usePrevTarget"/></dd>
			</dl>
			</div>');

		function updateProps() {
			var input = element.find("input");
			updateInstance();
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
		getShaderDefinition();

		var group = new hide.Element('<div class="group" name="Shader"></div>');
		var props = [];
		for(v in shaderDef.shader.data.vars) {
			if( v.kind != Param )
				continue;
			if( v.qualifiers != null && v.qualifiers.contains(Ignore) )
				continue;
			var prop = makeShaderParam(v);
			if( prop == null ) continue;
			props.push({name: v.name, t: prop, def: Reflect.field(this.props, v.name)});
		}
		group.append(hide.comp.PropsEditor.makePropsList(props));
		ectx.properties.add(group, this.props, function(pname) {
			ectx.onChange(this, pname);
			updateInstance(pname);

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

	static var _ = Prefab.register("rfx.screenShaderGraph", ScreenShaderGraph);

}