package hrt.prefab.fx;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;

typedef ShaderParam = {
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

	public function setTime(time: Float) {
		for(param in params) {
			var v = param.def;
			var val : Dynamic;
			switch(v.type) {
			case TFloat: val = getFloat(param.value, time);
			case TInt: val = hxd.Math.round(getFloat(param.value, time));
			case TBool: val = getFloat(param.value, time) >= 0.5;
			case TVec(_, VFloat): val = getVector(param.value, time);
			default:
				continue;
			}
			Reflect.setProperty(shader, v.name, val);
		}
	}
}

class ShaderDynAnimation extends ShaderAnimation {

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
					var val = getVector(param.value, time);
					shader.setParamValue(v, val);
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

class BaseFX extends hrt.prefab.Library {

	@:s public var duration : Float;
	@:c public var scriptCode : String;
	@:c public var cullingRadius : Float;
	@:c public var markers : Array<{t: Float}> = [];

	public function new() {
		super();
		duration = 5.0;
		scriptCode = null;
		cullingRadius = 1000;
	}

	override function save() {
		var obj : Dynamic = super.save();
		if( markers != null && markers.length > 0 )
			obj.markers = markers;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		markers = obj.markers == null ? [] : obj.markers;
	}

	public static function makeShaderParams(ctx: Context, shaderElt: hrt.prefab.Shader) {
		var shaderDef = shaderElt.getShaderDefinition(ctx);
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = [];

		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;

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
					ret.push({
						def: v,
						value: val
					});

				default:
					var base = 1.0;
					if(Std.isOfType(prop, Float) || Std.isOfType(prop, Int))
						base = cast prop;
					var curve = Curve.getCurve(shaderElt, v.name);
					var val = Value.VConst(base);
					if(curve != null)
						val = Value.VCurveScale(curve, base);
					ret.push({
						def: v,
						value: val
					});
			}
		}

		return ret;
	}

	public static function getShaderAnims(ctx: Context, elt: PrefabElement, anims: Array<ShaderAnimation>) {
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getShaderAnims(ctx, c, anims);
			}
		}

		var shader = elt.to(hrt.prefab.Shader);
		if(shader == null)
			return;

		for(shCtx in ctx.shared.getContexts(elt)) {
			if(shCtx.custom == null) continue;
			var anim = Std.isOfType(shCtx.custom,hxsl.DynamicShader) ? new ShaderDynAnimation(new hxd.Rand(0)) : new ShaderAnimation(new hxd.Rand(0));
			anim.shader = shCtx.custom;
			anim.params = makeShaderParams(ctx, shader);
			anims.push(anim);
		}
	}

	public function getFXRoot( ctx : Context, elt : PrefabElement ) : PrefabElement {
		if( elt.name == "FXRoot" )
			return elt;
		else {
			for(c in elt.children) {
				var elt = getFXRoot(ctx, c);
				if(elt != null) return elt;
			}
		}
		return null;
	}

	#if editor
	public function refreshObjectAnims(ctx: Context) { }
	#end
}