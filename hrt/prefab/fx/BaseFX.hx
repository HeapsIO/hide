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

class ShaderAnimation extends Evaluator {
	public var params : ShaderParams;
	public var shader : hxsl.Shader;
	var vector4 = new h3d.Vector4();
	var vector = new h3d.Vector();

	public function setTime(time: Float) {
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

	static var tmpVec = new h3d.Vector();
	var vectors : Array<h3d.Vector4>;
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
				case TVec(size, VFloat):
					if(vectors == null)
						vectors = [];
					var vec = vectors[param.idx];
					if(vec == null) {
						vec = new h3d.Vector4();
						vectors[param.idx] = vec;
					}
					getVector(param.value, time, vec);
					if( size < 4 ) {
						var tmpVec = tmpVec;
						tmpVec.set(vec.x, vec.y, vec.z);
						shader.setParamValue(v, tmpVec);
					} else
						shader.setParamValue(v, vec);
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
	?scale: Value,
	?rotation: Value,
	?color: Value,
	?visibility: Value,
	?additionalProperies : AdditionalProperies
};

interface BaseFX {

	@:s public var duration : Float;
	@:s public var startDelay : Float;
	@:c public var scriptCode : String;
	@:c public var cullingRadius : Float;
	@:c public var blendFactor : Float;
	@:s public var markers : Array<{t: Float}>;

	#if editor
	public function refreshObjectAnims() : Void;
	#end
}

class BaseFXTools {
	public static var useAutoPerInstance = true;

	public static function makeShaderParams(shaderElt: hrt.prefab.Shader) {
		var shaderDef = shaderElt.getShaderDefinition();
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = null;

		var paramCount = 0;
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;

			paramCount++;

			var prop = Reflect.field(shaderElt.props, v.name);
			if(prop == null)
				prop = hrt.prefab.DynamicShader.getDefault(v.type);

			var curves = Curve.getCurves(shaderElt, v.name);
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
					var curve = Curve.getCurve(shaderElt, v.name);
					var val = Value.VConst(base);
					if(curve != null)
						val = Value.VCurveScale(curve, base);
					if(ret == null) ret = [];
					ret.push({
						idx: paramCount - 1,
						def: v,
						value: val
					});
			}
		}

		return ret;
	}

	static var emptyParams : Array<String> = [];
	public static function getShaderAnims(elt: PrefabElement, anims: Array<ShaderAnimation>, ?batch: h3d.scene.MeshBatch) {
		// Init all animations recursively except Emitter ones (called in Emitter)
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getShaderAnims(c, anims, batch);
			}
		}

		var shader = elt.to(hrt.prefab.Shader);
		if(shader == null)
			return;

		var params = makeShaderParams(shader);

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