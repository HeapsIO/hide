package hrt.prefab.fx;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.Value as Value;

import hrt.prefab.fx.Evaluator;

typedef ShaderParam = {
	idx: Int,
	def: hxsl.Ast.TVar,
	value: Value
};

enum AdditionalProperies {
	None;
	PointLight(color : Value, power : Value, size : Value, range : Value );
	SpotLight(color : Value, power : Value, range : Value, angle : Value, fallOff : Value );
	DirLight(color : Value, power : Value);
}

typedef ShaderParams = Array<ShaderParam>;

/*
	Basic class used to animate custom properties with curves
	in FX.
*/
class CustomAnimation extends Evaluator {
	/** This animation will need to keep being updated if setTime was called once **/
	public var finishSync : Bool = false;
	public var startedPlaying : Bool = false;
	/** Under an emitter: the particle whose randoms the values use **/
	public var particle : Int = 0;

	public function setTime(time: Float) {
		throw "This method should overrided!";
	}
}

class RendererFXAnimation extends CustomAnimation {
	public var params : Array<{field : hrt.prefab.Prefab.PrefabField, value : Value}>;
	public var rfx : hrt.prefab.rfx.RendererFX;

	override public function setTime(time: Float) {
		for(param in params) {
			Reflect.setField(rfx, param.field.name, getFloat(param.value, time));
		}
	}
}

class ScreenShaderGraphFXAnimation extends CustomAnimation {
	public var params : Array<{name : String, type: hxsl.Ast.Type, value : Value}>;
	public var rfx : hrt.prefab.rfx.ScreenShaderGraph;

	static var vector4 = new h3d.Vector4();
	override public function setTime(time: Float) {
		for(param in params) {
			switch(param.type) {
				case TFloat:
					Reflect.setField(rfx.props, param.name, getFloat(param.value, time));
				case TVec(4, VFloat):
					getVector(param.value, time, vector4);
					Reflect.setProperty(rfx.props, param.name, vector4.toColor());
				case TVec(n, VFloat):
					getVector(param.value, time, vector4);
					var arr = Reflect.getProperty(rfx.props, param.name);
					if (arr == null) {
						arr = [];
						Reflect.setField(rfx.props, param.name, arr);
					}
					if (!(arr is Array))
						throw "unsupported";
					if (n > 0)
						arr[0] = vector4.x;
					if (n > 1)
						arr[1] = vector4.y;
					if (n > 2)
						arr[2] = vector4.z;
					if (n > 3)
						arr[3] = vector4.w;
				default:
					throw "unsupported";
			}
		}
	}
}

class ShaderAnimation extends CustomAnimation {
	public var params : ShaderParams;
	public var shader : hxsl.Shader;
	var vector4 = new h3d.Vector4();
	var vector = new h3d.Vector();

	override public function setTime(time: Float) {
		for(param in params) {
			var v = param.def;
			var val : Dynamic;
			switch(v.type) {
			case TFloat:
				var v = getFloat(particle, param.value, time);
				shader.setParamIndexFloatValue(param.idx, v);
				continue;
			case TInt: val = hxd.Math.round(getFloat(particle, param.value, time));
			case TBool: val = getFloat(particle, param.value, time) >= 0.5;
			case TVec(4, VFloat):
				getVector(particle, param.value, time, vector4);
				val = vector4;
			case TVec(_, VFloat):
				getVector(particle, param.value, time, vector4);
				vector.set(vector4.x, vector4.y, vector4.z);
				val = vector;
			default:
				continue;
			}
			shader.setParamIndexValue(param.idx, val);
		}
	}
}

class ShaderDynAnimation extends ShaderAnimation {
	var tmpVector4 = new h3d.Vector4();
	override function setTime(time: Float) {
		var shader : hxsl.DynamicShader = cast shader;
		for(param in params) {
			var v = param.def;
			switch(v.type) {
				case TFloat:
					var val = getFloat(particle, param.value, time);
					shader.setParamFloatValue(v, val);
				case TInt:
					var val = hxd.Math.round(getFloat(particle, param.value, time));
					shader.setParamValue(v, val);
				case TBool:
					var val = getFloat(particle, param.value, time) >= 0.5;
					shader.setParamValue(v, val);
				case TVec(4, VFloat):
					var index = shader.getParamIndex(v);
					var vector = shader.getParamValue(index);
					if (vector == null) {
						vector = new h3d.Vector4();
						shader.setParamValue(v, vector);
					}
					getVector(particle, param.value, time, vector);
				case TVec(_, VFloat):
					var index = shader.getParamIndex(v);
					var vector = shader.getParamValue(index);
					if (vector == null) {
						vector = new h3d.Vector();
						shader.setParamValue(v, vector);
					}
					getVector(particle, param.value, time, tmpVector4);
					vector.set(tmpVector4.x, tmpVector4.y, tmpVector4.z);
				default:
			}
		}
	}
}

typedef ObjectAnimation = {
	?elt: hrt.prefab.Object3D,
	?obj: h3d.scene.Object,
	?elt2d: hrt.prefab.Object2D,
	?obj2d: h2d.Object,
	?position: Value,
	?localPosition: Value,
	?scale: Value,
	?rotation: Value,
	?localRotation: Value,
	?color: Value,
	?visibility: Value,
	?additionalProperies : AdditionalProperies
};

interface BaseFX {

	@:s public var duration : Float;
	@:s public var startDelay : Float;
	@:c public var scriptCode : String;
	@:c public var cullingRadius : Float;
	@:s public var markers : Array<{t: Float}>;

	#if editor
	public function refreshObjectAnims() : Void;
	#end
}

class BaseFXTools {
	public static var useAutoPerInstance = true;

	public static function makeShaderParams(basePrefab: hrt.prefab.Prefab, shaderDef: hxsl.SharedShader) {
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = null;

		var paramCount = 0;
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;

			paramCount++;

			var prop = Reflect.field(basePrefab.props, v.name);
			if (prop == null)
				prop = Reflect.field(basePrefab, v.name);
			if (prop == null)
				prop = hrt.prefab.DynamicShader.getDefault(v.type);

			var curves = Curve.getCurves(basePrefab, v.name);
			if(curves == null || curves.length == 0)
				continue;

			switch(v.type) {
				case TVec(_, VFloat) :
					var isColor = v.name.toLowerCase().indexOf("color") >= 0;
					var val = isColor ? Curve.getColorValue(curves) : Curve.getVectorValue(curves);
					if(ret == null) ret = [];
					ret.push({
						idx: paramCount - 1,
						def: v,
						value: val,
					});

				default:
					var base = 1.0;
					if(Std.isOfType(prop, Float) || Std.isOfType(prop, Int))
						base = cast prop;
					var curve = Curve.getCurve(basePrefab, v.name);
					var val = Value.VConst(base);
					if(curve != null)
						val = Value.VMult(curve.makeVal(), VConst(base));
					if(ret == null) ret = [];
					ret.push({
						idx: paramCount - 1,
						def: v,
						value: val,
					});
			}
		}

		return ret;
	}

	/**
		The params of a shader under an emitter, evaluated over the particle life: the modes of
		`Shader.particleParams` (see `EmitterParam`), colors excepted, which keep their curves.
	**/
	public static function makeParticleShaderParams(shader: hrt.prefab.Shader, shaderDef: hxsl.SharedShader, params: hrt.prefab.fx.EmitterParam.ParamBuilder) : ShaderParams {
		if(shaderDef == null)
			return null;
		var ret : ShaderParams = null;
		var paramCount = 0;
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;
			paramCount++;
			var val = switch(v.type) {
				case TVec(_, VFloat) if(v.name.toLowerCase().indexOf("color") >= 0):
					var curves = Curve.getCurves(shader, v.name);
					curves == null || curves.length == 0 ? null : Curve.getColorValue(curves);
				case TVec(n, VFloat): makeParticleShaderValue(shader, v.name, n, params);
				case TFloat, TInt, TBool: makeParticleShaderValue(shader, v.name, 1, params);
				default: null;
			}
			if(val == null)
				continue;
			if(ret == null) ret = [];
			ret.push({
				idx: paramCount - 1,
				def: v,
				value: val,
			});
		}
		return ret;
	}

	/**
		The value of the param `name` of a shader under an emitter, `dim` its number of components
		(1 for a float, a vector has at least 3, w is 1 when not given). Null when it is not animated.
		An unset component takes the value of the shader prop.
	**/
	public static function makeParticleShaderValue(shader: hrt.prefab.Shader, name: String, dim: Int, params: hrt.prefab.fx.EmitterParam.ParamBuilder) : Null<Value> {
		var value = shader.getParticleParam(name);
		if(value == null)
			return null;
		var prop : Dynamic = Reflect.field(shader.props, name);
		inline function base(i: Int) : Float {
			var v : Dynamic = dim == 1 ? prop : (Std.isOfType(prop, Array) ? (prop : Array<Dynamic>)[i] : null);
			return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? v : 0.0;
		}
		var key = shader.getAbsPath(true) + "." + name;
		if(dim == 1)
			return params.comp(key, value[0], base(0), shader);
		var c = [for(i in 0...dim) params.comp(key + "." + hrt.prefab.fx.EmitterParam.COMPONENTS[i], value[i], base(i), shader)];
		return VVector(c[0], c[1], dim > 2 ? c[2] : VZero, dim > 3 ? c[3] : null);
	}

	public static function makeRendererFXParams(rfxElt: hrt.prefab.rfx.RendererFX) {
		var classRfx = Type.getClass(cast rfxElt);
		var originalProps : Array<Dynamic> = @:privateAccess Prefab.getSerializablePropsForClass(classRfx);
		var serializedProps : Array<Dynamic> = originalProps.copy();
		var ret : Array<{field : hrt.prefab.Prefab.PrefabField, value : Value}> = null;
		for (f in serializedProps) {
			if (!(Reflect.field(rfxElt, f.name) is Float))
				continue;

			var curves = Curve.getCurves(rfxElt, f.name);
			if(curves == null || curves.length == 0)
				continue;

			var base = 1.0;
			var curve = Curve.getCurve(rfxElt, f.name);
			var val = Value.VConst(base);
			if(curve != null)
				val = Value.VMult(curve.makeVal(), VConst(base));
			if(ret == null) ret = [];
			ret.push({
				field : f,
				value : val
			});
		}

		return ret;
	}

	static var emptyParams : Array<String> = [];
	/**
		`particleParams`: the shaders are under an emitter, their params are evaluated over the
		particle life and allocate their random slots there.
	**/
	public static function getCustomAnimations(elt: PrefabElement, anims: Array<CustomAnimation>, ?batch: h3d.scene.MeshBatch, ?particleParams: hrt.prefab.fx.EmitterParam.ParamBuilder) {
		// Init all animations recursively except Emitter ones (called in Emitter)
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getCustomAnimations(c, anims, batch, particleParams);
			}
		}

		var shader = elt.to(hrt.prefab.Shader);
		if (shader != null && shader.shader != null && !Std.isOfType(shader.shader, hrt.prefab.fx.gpuemitter.ComputeUtils) ) {
			var params = particleParams != null ? makeParticleShaderParams(shader, shader.getShaderDefinition(), particleParams) : makeShaderParams(shader, shader.getShaderDefinition());
			var shader = shader.shader;

			if(useAutoPerInstance && batch != null) @:privateAccess {
				var perInstance = batch.instancedParams;
				if ( perInstance == null ) {
					perInstance = new hxsl.Cache.BatchInstanceParams([]);
					batch.instancedParams = perInstance;
				}
				perInstance.forcedPerInstance.push({
					shader: shader.shader.data.name,
					params: params == null ? emptyParams : params.map(p -> p.def.name)
				});
			}

			if(params != null) {
				var anim = Std.isOfType(shader,hxsl.DynamicShader) ? new ShaderDynAnimation() : new ShaderAnimation();
				anim.shader = shader;
				anim.params = params;
				anims.push(anim);
			}

			if(batch != null) {
				var shaderPrefab = Std.downcast(elt, hrt.prefab.Shader);
				@:privateAccess shaderPrefab.applyShader(batch, batch.material, shader);
			}
		}

		var rendererFX = elt.to(hrt.prefab.rfx.RendererFX);
		if (rendererFX != null && rendererFX.enabled) {
			var screenShaderGraph = elt.to(hrt.prefab.rfx.ScreenShaderGraph);
			if (screenShaderGraph != null) {
				var params = makeShaderParams(screenShaderGraph, screenShaderGraph.getShaderDefinition());
				if (params != null) {
					var anim = new ScreenShaderGraphFXAnimation();
					anim.params = [for (param in params)
						{ name: param.def.name, type:param.def.type, value: param.value}
					];
					anim.rfx = cast @:privateAccess screenShaderGraph.instance;
					anims.push(anim);
					anim.finishSync = true;
				}
			}
			else {
				var params = makeRendererFXParams(rendererFX);
				if (params != null) {
					var anim = new RendererFXAnimation();
					anim.params = params;
					anim.rfx = @:privateAccess rendererFX.instance;
					anims.push(anim);
					anim.finishSync = true;
				}
			}
		}
	}

	public static function getFXRoot(elt : PrefabElement ) : PrefabElement {
		if( elt.name == "FXRoot" )
			return elt;
		else {
			for(c in elt.children) {
				var elt = getFXRoot(c);
				if(elt != null) return elt;
			}
		}
		return null;
	}

	#if editor
	public function refreshObjectAnims() { }
	#end
}