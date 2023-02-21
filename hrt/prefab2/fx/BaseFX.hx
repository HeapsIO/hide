package hrt.prefab2.fx;
import hrt.prefab2.Curve;
import hrt.prefab2.Prefab as PrefabElement;
import hrt.prefab2.fx.Value as Value;

import hrt.prefab2.fx.Evaluator;

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
			case TVec(_, VFloat):
				getVector(param.value, time, vector);
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
				case TVec(_, VFloat):
					getVector(param.value, time, tmpVec);
					shader.setParamValue(v, tmpVec);
				default:
			}
		}
	}
}

typedef ObjectAnimation = {
	?elt: hrt.prefab2.Object3D,
	?obj: h3d.scene.Object,
	?elt2d: hrt.prefab.Object2D,
	?obj2d: h2d.Object,
	events: Array<hrt.prefab2.fx.Event.EventInstance>,
	?position: Value,
	?scale: Value,
	?rotation: Value,
	?color: Value,
	?visibility: Value,
	?additionalProperies : AdditionalProperies
};

class BaseFX extends Object3D {

	@:s public var duration : Float;
	@:s public var startDelay : Float;
	@:c public var scriptCode : String;
	@:c public var cullingRadius : Float;
	@:c public var markers : Array<{t: Float}> = [];

	public function new() {
		super();
		duration = 5.0;
		scriptCode = null;
		cullingRadius = 1000;
	}

	/*override function save(data: Dynamic) : Dynamic {
		super.save(data);
		if( markers != null && markers.length > 0 )
			data.markers = markers;
	}*/

	override function load( obj : Dynamic ) {
		super.load(obj);
		markers = obj.markers == null ? [] : obj.markers;
	}

	public static function makeShaderParams(shaderElt: hrt.prefab2.Shader) {
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

	public static function getShaderAnims(elt: PrefabElement, anims: Array<ShaderAnimation>) {
		if(Std.downcast(elt, hrt.prefab2.fx.Emitter) == null) {
			for(c in elt.children) {
				getShaderAnims(c, anims);
			}
		}

		var shader = elt.to(hrt.prefab2.Shader);
		if(shader == null)
			return;

		if (shader.shader != null) {
			var params = makeShaderParams(shader);
			if(params != null) {
				var anim = Std.isOfType(shader.shader,hxsl.DynamicShader) ? new ShaderDynAnimation() : new ShaderAnimation();
				anim.shader = shader.shader;
				anim.params = params;
				anims.push(anim);
			}
		}

	}

	public function getFXRoot(elt : PrefabElement ) : PrefabElement {
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