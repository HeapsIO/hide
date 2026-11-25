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

class ParamAnimation {
	public var syncCulled : Bool = false;
	public var startedPlaying : Bool = false;
	public var evaluator : Evaluator;

	public function new(?evaluator: Evaluator) {
		this.evaluator = evaluator ?? new Evaluator();
	}

	inline function getFloat(v: Value, time: Float) return evaluator.getFloat(v, time);
	inline function getVector(v: Value, time: Float, vec: h3d.Vector4) return evaluator.getVector(v, time, vec);

	public function setTime(time: Float) {
		throw "not implemented";
	}
}

class RendererFXAnimation extends ParamAnimation {
	public var data : RendererFXAnimData;
	public var rfx : hrt.prefab.rfx.RendererFX;

	public function new(data, rfx, ?evaluator) {
		super(evaluator);
		this.data = data;
		this.rfx = rfx;
		// a renderer FX shows on the whole screen, the FX culled or not
		syncCulled = true;
	}

	static var vector4 = new h3d.Vector4();
	override public function setTime(time: Float) {
		var target : Dynamic = Std.isOfType(rfx, hrt.prefab.rfx.ScreenShaderGraph) ? rfx.props : rfx;
		for(param in data.params) {
			switch(param.type) {
				case TFloat:
					Reflect.setField(target, param.name, getFloat(param.value, time));
				case TVec(4, VFloat):
					getVector(param.value, time, vector4);
					Reflect.setProperty(target, param.name, vector4.toColor());
				case TVec(n, VFloat):
					getVector(param.value, time, vector4);
					var arr = Reflect.getProperty(target, param.name);
					if (arr == null) {
						arr = [];
						Reflect.setField(target, param.name, arr);
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

class ShaderAnimation extends ParamAnimation {
	public var data : ShaderAnimData;
	public var shader : hxsl.Shader;
	var vector4 = new h3d.Vector4();
	var vector = new h3d.Vector();

	public function new(data, shader, ?evaluator) {
		super(evaluator);
		this.data = data;
		this.shader = shader;
	}

	override public function setTime(time: Float) {
		for(param in data.params) {
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
		for(param in data.params) {
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

typedef ObjectAnimData = {
	elt: hrt.prefab.Object3D,
	?position: VectorAnimation,
	?scale: VectorAnimation,
	?rotation: VectorAnimation,
	?color: Value,
	?visibility: Value,
	?additionalProperies : AdditionalProperies
};

typedef ObjectAnimation2D = {
	elt2d: hrt.prefab.Object2D,
	obj2d: h2d.Object,
	?position: VectorAnimation,
	?scale: VectorAnimation,
	?rotation: VectorAnimation,
	?color: Value,
	?visibility: Value,
};

typedef ShaderAnimData = {
	prefab: hrt.prefab.Shader,
	params: ShaderParams,
	perInstance: Array<String>,
};

typedef RendererFXParam = { name : String, type : hxsl.Ast.Type, value : Value };

typedef RendererFXAnimData = {
	prefab: hrt.prefab.rfx.RendererFX,
	params: Array<RendererFXParam>,
};

/** The parameters of a sub FX animated by curves of the SubFX, in the time of the FX that has it **/
typedef SubFXAnimData = {
	prefab: SubFX,
	params: Array<{ name: String, value: Value }>,
};

typedef SubFXAnimation = {
	anim: hrt.prefab.fx.FX.FXAnimation,
	data: SubFXAnimData,
};


class AnimData {
	public var objects : Array<ObjectAnimData> = [];
	public var shaders : Array<ShaderAnimData> = [];
	public var effects : Array<RendererFXAnimData> = [];
	/** null when no sub FX has an animated parameter **/
	public var subFXs : Array<SubFXAnimData>;

	public function new(?root: PrefabElement) {
		if(root == null)
			return;
		function rec(elt: PrefabElement) {
			// Emitter resolve their own animations
			if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
				for(c in BaseFXTools.getAnimatedChildren(elt)) {
					if(@:privateAccess c.shouldBeInstanciated())
						rec(c);
				}
			}

			var obj3d = elt.to(hrt.prefab.Object3D);
			if(obj3d != null) {
				var anim = objectAnim(obj3d, obj3d.local3d);
				if(anim != null)
					objects.push(anim);
			}

			var shader = elt.to(hrt.prefab.Shader);
			if(shader != null) {
				var s = shaderData(shader);
				if(s.params != null)
					shaders.push(s);
			}

			var e = effectData(elt);
			if(e != null)
				effects.push(e);

			var sub = Std.downcast(elt, SubFX);
			if(sub != null) {
				var s = subFXData(sub);
				if(s != null) {
					if(subFXs == null) subFXs = [];
					subFXs.push(s);
				}
			}
		}
		rec(root);
	}

	public static function ofShaders(shaders: Array<hrt.prefab.Shader>, particle = false) : AnimData {
		var d = new AnimData();
		// the shaders without curves too: bindParams applies them to the batch
		d.shaders = [for(s in shaders) shaderData(s, particle)];
		return d;
	}

	public function bindObjects() : Array<h3d.scene.Object> {
		return [for(a in objects) a.elt.local3d];
	}

	public function bindParams(?evaluator: Evaluator, ?batch: h3d.scene.MeshBatch) : Array<ParamAnimation> {
		var anims = [];
		for(s in shaders)
			bindShader(s, anims, evaluator, batch);
		for(e in effects)
			bindEffect(e, anims, evaluator);
		return anims;
	}

	public function bindSubFXs() : Array<SubFXAnimation> {
		if(subFXs == null)
			return null;
		var ret = null;
		for(s in subFXs) {
			var anim = Std.downcast(s.prefab.refInstance?.findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
			if(anim == null)
				continue;
			if(ret == null) ret = [];
			ret.push({ anim: anim, data: s });
		}
		return ret;
	}

	public static var useAutoPerInstance = true;

	static function subFXData(sub: SubFX) : SubFXAnimData {
		// most sub FX have no curve
		if(!Lambda.exists(sub.children, c -> c.enabled && Std.isOfType(c, Curve)))
			return null;
		var fx = Std.downcast(sub.refInstance, FX);
		if(fx == null)
			return null;
		var params = null;
		for(p in fx.parameters) {
			var c = Curve.getCurve(sub, SubFX.paramCurveName(p.name));
			if(c == null)
				continue;
			if(params == null) params = [];
			params.push({ name: p.name, value: c.makeVal() });
		}
		return params == null ? null : { prefab: sub, params: params };
	}

	static function objectAnim(obj3d: hrt.prefab.Object3D, local3d: h3d.scene.Object) : ObjectAnimData {
		var elt : PrefabElement = obj3d;
		// most objects have no curve: none of the lookups below would find one
		if(!Lambda.exists(elt.children, c -> c.enabled && Std.isOfType(c, Curve)))
			return null;
		var anyFound = false;

		function makeVal(name, def) : Value {
			var c = Curve.getCurve(elt, name);
			if(c != null)
				anyFound = true;

			if (c == null)
				return def;
			return c.makeVal();
		}

		function makeColor(name: String) {
			var curves = Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;
			return BaseFXTools.getColorValue(curves);
		}

		var ap : AdditionalProperies = null;

		if( Std.isOfType(local3d, h3d.scene.pbr.PointLight)) {
			ap = PointLight(makeColor("color"), makeVal("power", null), makeVal("size", null), makeVal("range", null) );
		}
		else if( Std.isOfType(local3d, h3d.scene.pbr.SpotLight)) {
			ap = SpotLight(makeColor("color"), makeVal("power", null), makeVal("range", null), makeVal("angle", null), makeVal("fallOff", null) );
		}
		else if( Std.isOfType(local3d, h3d.scene.pbr.DirLight)) {
			ap = DirLight(makeColor("color"), makeVal("power", null));
		}

		var anim : ObjectAnimData = {
			elt: obj3d,
			position: BaseFXTools.vectorAnimation(elt, "position"),
			scale: BaseFXTools.vectorAnimation(elt, "scale"),
			rotation: BaseFXTools.vectorAnimation(elt, "rotation"),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
			additionalProperies: ap,
		};
		return anyFound || anim.position != null || anim.scale != null || anim.rotation != null ? anim : null;
	}

	static function shaderParams(basePrefab: hrt.prefab.Prefab, shaderDef: hxsl.SharedShader, particle = false) {
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = null;

		var paramCount = 0;
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;

			paramCount++;

			var size = particle ? EmitterParam.getParamSize(v) : 0;
			var val = size > 0 ? particleValue(cast basePrefab, v.name, size) : shaderValue(basePrefab, v.name, v.type);
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

	static function shaderValue(basePrefab: hrt.prefab.Prefab, name: String, type: hxsl.Ast.Type) : Value {
		var curves = Curve.getCurves(basePrefab, name);
		if(curves == null || curves.length == 0)
			return null;
		switch(type) {
			case TVec(_, VFloat):
				return name.toLowerCase().indexOf("color") >= 0 ? BaseFXTools.getColorValue(curves) : BaseFXTools.getVectorValue(curves);
			default:
				return Curve.getCurve(basePrefab, name)?.makeVal();
		}
	}

	static function particleValue(shader: hrt.prefab.Shader, name: String, size: Int) : Value {
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

	static function effectParams(rfxElt: hrt.prefab.rfx.RendererFX) {
		var classRfx = Type.getClass(cast rfxElt);
		var originalProps : Array<Dynamic> = @:privateAccess Prefab.getSerializablePropsForClass(classRfx);
		var serializedProps : Array<Dynamic> = originalProps.copy();
		var ret : Array<RendererFXParam> = null;
		for (f in serializedProps) {
			if (!(Reflect.field(rfxElt, f.name) is Float))
				continue;

			var curve = Curve.getCurve(rfxElt, f.name);
			if(curve == null)
				continue;
			if(ret == null) ret = [];
			ret.push({
				name : f.name,
				type : TFloat,
				value : curve.makeVal()
			});
		}

		return ret;
	}

	static function shaderData(shader: hrt.prefab.Shader, particle = false) : ShaderAnimData {
		var params = shaderParams(shader, shader.getShaderDefinition(), particle);
		return { prefab: shader, params: params, perInstance: params == null ? emptyParams : [for(p in params) p.def.name] };
	}

	static function effectData(elt: PrefabElement) : RendererFXAnimData {
		var rendererFX = elt.to(hrt.prefab.rfx.RendererFX);
		if (rendererFX == null || !rendererFX.enabled)
			return null;
		var screenShaderGraph = elt.to(hrt.prefab.rfx.ScreenShaderGraph);
		if (screenShaderGraph != null) {
			var params = shaderParams(screenShaderGraph, screenShaderGraph.getShaderDefinition());
			if (params == null)
				return null;
			return { prefab: rendererFX, params: [for (param in params) { name: param.def.name, type: param.def.type, value: param.value }] };
		}
		var params = effectParams(rendererFX);
		return params == null ? null : { prefab: rendererFX, params: params };
	}

	static var emptyParams : Array<String> = [];
	static function bindShader(data: ShaderAnimData, anims: Array<ParamAnimation>, evaluator: Evaluator, batch: h3d.scene.MeshBatch) {
		var shader = data.prefab.shader;
		if (shader == null || Std.isOfType(shader, hrt.prefab.fx.gpuemitter.ComputeUtils))
			return;
		var params = data.params;

		if(useAutoPerInstance && batch != null) @:privateAccess {
			var perInstance = batch.instancedParams;
			if ( perInstance == null ) {
				perInstance = new hxsl.Cache.BatchInstanceParams([]);
				batch.instancedParams = perInstance;
			}
			perInstance.forcedPerInstance.push({
				shader: shader.shader.data.name,
				params: data.perInstance
			});
		}

		if(params != null)
			anims.push(Std.isOfType(shader,hxsl.DynamicShader) ? new ShaderDynAnimation(data, shader, evaluator) : new ShaderAnimation(data, shader, evaluator));

		if(batch != null)
			@:privateAccess data.prefab.applyShader(batch, batch.material, shader);
	}

	static function bindEffect(data: RendererFXAnimData, anims: Array<ParamAnimation>, evaluator: Evaluator) {
		anims.push(new RendererFXAnimation(data, @:privateAccess data.prefab.instance, evaluator));
	}
}

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

}