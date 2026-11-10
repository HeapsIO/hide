package hrt.prefab.fx;
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

// Supports overriding xyz components separately
typedef VectorAnimation = { ?x: Value, ?y: Value, ?z: Value };

typedef ObjectAnimation = {
	?elt: hrt.prefab.Object3D,
	?obj: h3d.scene.Object,
	?elt2d: hrt.prefab.Object2D,
	?obj2d: h2d.Object,
	?position: VectorAnimation,
	?scale: VectorAnimation,
	?rotation: VectorAnimation,
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

	public static function makeShaderParams(basePrefab: hrt.prefab.Prefab, shaderDef: hxsl.SharedShader, particle = false) {
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = null;

		var paramCount = 0;
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;

			paramCount++;

			var size = particle ? EmitterParam.getParamSize(v) : 0;
			var val = size > 0 ? makeParticleShaderValue(cast basePrefab, v.name, size) : makeShaderParamValue(basePrefab, v.name, v.type);
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

	public static function getVectorValue(curves: Array<Curve>, defVal: Float=0.0) : Value {
		inline function find(s) {
			return findSuffix(curves, s);
		}
		var x = find(":x");
		var y = find(":y");
		var z = find(":z");

		inline function curveOrVal(c: Curve, defVal: Float) : Value {
			return c == null ? VConst(defVal) : c.makeVal();
		}

		return VVector(
			curveOrVal(x, defVal),
			curveOrVal(y, defVal),
			curveOrVal(z, defVal));
	}

	public static function getColorValue(curves: Array<Curve>) : Value {
		inline function find(s) {
			return findSuffix(curves, s);
		}

		var r = find(":r");
		var g = find(":g");
		var b = find(":b");
		var a = find(":a");
		var h = find(":h");
		var s = find(":s");
		var l = find(":l");

		if(h != null || s != null || l != null) {
			return VHsl(
				h != null ? h.makeVal() : VConst(0.0),
				s != null ? s.makeVal() : VConst(1.0),
				l != null ? l.makeVal() : VConst(1.0),
				a != null ? a.makeVal() : VConst(1.0));
		}

		if(a != null && r == null && g == null && b == null)
			return a.makeVal();

		if(a == null && r == null && g == null && b == null)
			return VConst(1.0); // White by default

		return VColor(
			r != null ? r.makeVal() : VConst(1.0),
			g != null ? g.makeVal() : VConst(1.0),
			b != null ? b.makeVal() : VConst(1.0),
			a != null ? a.makeVal() : VConst(1.0));
	}

	static inline function findSuffix(curves: Array<Curve>, suffix: String) {
		return Lambda.find(curves, c -> StringTools.endsWith(c.name.toLowerCase(), suffix));
	}

	public static function makeShaderParamValue(basePrefab: hrt.prefab.Prefab, name: String, type: hxsl.Ast.Type) : Value {
		var curves = Curve.getCurves(basePrefab, name);
		if(curves == null || curves.length == 0)
			return null;
		switch(type) {
			case TVec(_, VFloat):
				return name.toLowerCase().indexOf("color") >= 0 ? getColorValue(curves) : getVectorValue(curves);
			default:
				return Curve.getCurve(basePrefab, name)?.makeVal();
		}
	}

	public static function makeParticleShaderValue(shader: hrt.prefab.Shader, name: String, size: Int) : Value {
		if(shader.particleParams == null)
			return null;
		var keys = [for(i in 0...size) EmitterParam.curveName(name, size, i)];
		inline function isCurve(i: Int) return switch(shader.particleParams.get(keys[i])) { case Curve: true; default: false; };
		if(![for(i in 0...size) isCurve(i)].contains(true))
			return null;
		var prop : Dynamic = Reflect.field(shader.props, name);
		function comp(i: Int) {
			var base = EmitterParam.baseComponent(prop, size, i);
			return isCurve(i) ? EmitterParam.ParamBuilder.curve(shader, keys[i], base) : Evaluator.vVal(base);
		}
		// 4 components: a color
		return size == 1 ? comp(0) : size > 3 ? VColor(comp(0), comp(1), comp(2), comp(3)) : VVector(comp(0), comp(1), size > 2 ? comp(2) : VZero);
	}

	public static function makeRendererFXParams(rfxElt: hrt.prefab.rfx.RendererFX) {
		var classRfx = Type.getClass(cast rfxElt);
		var originalProps : Array<Dynamic> = @:privateAccess Prefab.getSerializablePropsForClass(classRfx);
		var serializedProps : Array<Dynamic> = originalProps.copy();
		var ret : Array<{field : hrt.prefab.Prefab.PrefabField, value : Value}> = null;
		for (f in serializedProps) {
			if (!(Reflect.field(rfxElt, f.name) is Float))
				continue;

			var curve = Curve.getCurve(rfxElt, f.name);
			if(curve == null)
				continue;
			if(ret == null) ret = [];
			ret.push({
				field : f,
				value : curve.makeVal()
			});
		}

		return ret;
	}

	public static function vectorAnimation(elt: PrefabElement, name: String) : VectorAnimation {
		var curves = Curve.getCurves(elt, name);
		if(curves == null || curves.length == 0)
			return null;
		if(curves.length == 1 && curves[0].name == name) {
			var v = curves[0].makeVal();
			return { x: v, y: v, z: v };
		}
		inline function comp(suffix: String) return Lambda.find(curves, c -> StringTools.endsWith(c.name.toLowerCase(), suffix))?.makeVal();
		return { x: comp(":x"), y: comp(":y"), z: comp(":z") };
	}

	/**
		Children of `elt`, plus the refInstance of a Reference so its content is animated by the FX.
		SubFX and references to FX are animated by their own FXAnimation.
	**/
	public static function getAnimatedChildren(elt: PrefabElement) : haxe.ds.ReadOnlyArray<PrefabElement> {
		var ref = Std.downcast(elt, hrt.prefab.Reference);
		if (ref == null || ref.refInstance == null || Std.isOfType(ref, SubFX) || Std.isOfType(ref.refInstance, FX) || @:privateAccess !ref.shouldBeInstanciated())
			return elt.children;
		return elt.children.concat([ref.refInstance]);
	}

	static var emptyParams : Array<String> = [];
	public static function getCustomAnimations(elt: PrefabElement, anims: Array<CustomAnimation>, ?batch: h3d.scene.MeshBatch, particle = false) {
		// Init all animations recursively except Emitter ones (called in Emitter)
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			for(c in getAnimatedChildren(elt)) {
				getCustomAnimations(c, anims, batch, particle);
			}
		}

		var shader = elt.to(hrt.prefab.Shader);
		if (shader != null && shader.shader != null && !Std.isOfType(shader.shader, hrt.prefab.fx.gpuemitter.ComputeUtils) ) {
			var params = makeShaderParams(shader, shader.getShaderDefinition(), particle);
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