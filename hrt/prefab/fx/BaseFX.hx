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
				var v = getFloat(param.value, time);
				shader.setParamIndexFloatValue(param.idx, v);
				continue;
			case TInt: val = hxd.Math.round(getFloat(param.value, time));
			case TBool: val = getFloat(param.value, time) >= 0.5;
			case TVec(4, VFloat):
				getVector(param.value, time, vector4);
				val = vector4;
			case TVec(_, VFloat):
				getVector(param.value, time, vector4);
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
					var val = getFloat(param.value, time);
					shader.setParamFloatValue(v, val);
				case TInt:
					var val = hxd.Math.round(getFloat(param.value, time));
					shader.setParamValue(v, val);
				case TBool:
					var val = getFloat(param.value, time) >= 0.5;
					shader.setParamValue(v, val);
				case TVec(4, VFloat):
					var index = shader.getParamIndex(v);
					var vector = shader.getParamValue(index);
					if (vector == null) {
						vector = new h3d.Vector4();
						shader.setParamValue(v, vector);
					}
					getVector(param.value, time, vector);
				case TVec(_, VFloat):
					var index = shader.getParamIndex(v);
					var vector = shader.getParamValue(index);
					if (vector == null) {
						vector = new h3d.Vector();
						shader.setParamValue(v, vector);
					}
					getVector(param.value, time, tmpVector4);
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
	events: Array<hrt.prefab.fx.Event.EventInstance>,
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
			if(prop == null)
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

	public static function makeRendererFXParams(rfxElt: hrt.prefab.rfx.RendererFX) {
		var serializedProps : Array<Dynamic> = @:privateAccess Prefab.getSerializablePropsForClass(Type.getClass(cast rfxElt)).copy();
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
	public static function getCustomAnimations(elt: PrefabElement, anims: Array<CustomAnimation>, ?batch: h3d.scene.MeshBatch) {
		// Init all animations recursively except Emitter ones (called in Emitter)
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getCustomAnimations(c, anims, batch);
			}
		}

		var shader = elt.to(hrt.prefab.Shader);
		if (shader != null && shader.shader != null && !Std.isOfType(shader.shader, hrt.prefab.fx.gpuemitter.ComputeUtils) ) {
			var params = makeShaderParams(shader, shader.getShaderDefinition());
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
				batch.material.mainPass.addShader(shader);
			}
		}

		var rendererFX = elt.to(hrt.prefab.rfx.RendererFX);
		if (rendererFX != null) {
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
				}
			}
			else {
				var params = makeRendererFXParams(rendererFX);
				if (params != null) {
					var anim = new RendererFXAnimation();
					anim.params = params;
					anim.rfx = @:privateAccess rendererFX.instance;
					anims.push(anim);
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