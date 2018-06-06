package hide.prefab.fx;
import hide.prefab.Curve;
import hide.prefab.fx.FXScene.Value;
import hide.prefab.fx.FXScene.Evaluator;
using Lambda;

enum EmitShape {
	Sphere;
	Circle;
}

typedef ParamType = hide.comp.PropsEditor.PropType;
// enum ParamType {
// 	TInt(?min: Int, ?max: Int);
// 	TFloat(?min: Float, ?max: Float);
// 	TVector(size: Int);
// }

typedef ParamDef = {
	> hide.comp.PropsEditor.PropDef,
	?noanim: Bool
}

typedef InstanceDef = {
	localSpeed: Value,
	localOffset: Value,
	scale: Value
}

typedef ShaderAnims = Array<hide.prefab.Shader.ShaderAnimation>;

@:allow(hide.prefab.fx.EmitterObject)
private class ParticleInstance extends Evaluator {
	var parent : EmitterObject;
	public var life = 0.0;
	public var obj : h3d.scene.Object;

	public var curVelocity = new h3d.Vector();
	public var curPos = new h3d.Vector();
	public var orientation = new h3d.Quat();
	//public var orientation = new h3d.Matrix();

	// public var speed : VectorParam;
	// public var localSpeed : VectorParam;
	// public var globalSpeed : VectorParam;
	// public var localOffset : VectorParam;
	public var def : InstanceDef;
	public var shaderAnims : ShaderAnims;

	public function new(parent: EmitterObject, def: InstanceDef) {
		super(parent.random);
		this.def = def;
		this.parent = parent;
		parent.instances.push(this);
	}

	public function update(dt : Float) {

		var localSpeed = getVector(def.localSpeed, life);
		if(localSpeed.length() > 0.001) {
			// var locSpeedVec = localSpeed.get(life);
			localSpeed.transform3x3(orientation.toMatrix());
			curVelocity = localSpeed;
		}
		// {
		// 	var globSpeedVec = new h3d.Vector(0, 0, -2);
		// 	curVelocity = curVelocity.add(globSpeedVec);
		// }

		curPos.x += curVelocity.x * dt;
		curPos.y += curVelocity.y * dt;
		curPos.z += curVelocity.z * dt;
		obj.setPos(curPos.x, curPos.y, curPos.z);

		var scaleVec = getVector(def.scale, life);
		obj.scaleX = scaleVec.x;
		obj.scaleY = scaleVec.y;
		obj.scaleZ = scaleVec.z;

		// if(localOffset != null) {
		// 	var off = localOffset.get(life);
		// 	obj.x += off.x;
		// 	obj.y += off.y;
		// 	obj.z += off.x;
		// }

		for(anim in shaderAnims) {
			anim.setTime(life);
		}

		life += dt;
	}

	public function remove() {
		obj.remove();
		parent.instances.remove(this);
	}
}

@:allow(hide.prefab.fx.ParticleInstance)
@:allow(hide.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public var particleTemplate : hide.prefab.Prefab;
	public var maxCount = 20;
	public var lifeTime = 2.0;
	// public var emitRate : FloatParam;
	public var emitShape : EmitShape = Circle;
	// public var emitShapeSize = new FloatParam(6.0);

	var emitRate : Value;
	var emitSize : Value;

	public var instDef : InstanceDef;

	// public var emitSpeed = new FloatParam(1.0);
	// public var localSpeed = new VectorParam();
	// public var partSpeed = new VectorParam();

	public function new(?parent) {
		super(parent);
		random = new hxd.Rand(0);
		evaluator = new Evaluator(random);
	}

	var random: hxd.Rand;
	var context : hide.prefab.Context;
	var emitCount = 0;
	var lastTime = -1.0;
	var curTime = 0.0;
	var evaluator : Evaluator;

	var instances : Array<ParticleInstance> = [];

	// public function new()


	function reset() {
		curTime = 0.0;
		lastTime = 0.0;
		emitCount = 0;
		for(inst in instances.copy()) {
			inst.remove();
		}
	}

	function doEmit(count: Int) {
		calcAbsPos();

		if(instDef == null)
			return;

		var shapeSize = evaluator.getFloat(emitSize, curTime);
		context.local3d = this.parent;
		if(particleTemplate == null)
			return;
		// var localTrans = new h3d.Matrix();
		for(i in 0...count) {
			var ctx = particleTemplate.makeInstance(context);
			var obj3d = ctx.local3d;

			var localPos = new h3d.Vector();
			var localDir = new h3d.Vector();
			switch(emitShape) {
				case Circle:
					var dx = 0.0, dy = 0.0;
					do {
						dx = hxd.Math.srand(1.0);
						dy = hxd.Math.srand(1.0);
					}
					while(dx * dx + dy * dy > 1.0);
					dx *= shapeSize / 2.0;
					dy *= shapeSize / 2.0;
					localPos.set(0, dx, dy);
					// localTrans.initTranslate(0, dx, dy);
				default:
			}

			localPos.transform(absPos);
			// localTrans.multiply(localTrans, absPos);
			var part = new ParticleInstance(this, instDef);
			part.obj = obj3d;
			part.curPos = localPos;
			// part.localSpeed = localSpeed.copy();
			//part.transform = localTrans;
			part.orientation.initRotateMatrix(absPos);
			// part.curVelocity

			part.shaderAnims = [];
			// var shaders = particleTemplate.getAll(hide.prefab.Shader);
			// for(shader in shaders) {
			// 	var params = shader.makeParams();
			// 	part.shaderAnims.push({

			// 	});
			// }
			var shaders = particleTemplate.getAll(hide.prefab.Shader);
			for(shader in shaders) {
				var shCtx = shader.makeInstance(ctx);
				if(shCtx == null)
					continue;
				var anim : hide.prefab.Shader.ShaderAnimation = cast shCtx.custom;
				if(anim != null) {
					part.shaderAnims.push(anim);
				}
			}
		}
		context.local3d = this;
		emitCount += count;
	}

	function tick(dt: Float) {
		// def.getSum(EmitRate, this);

		var emitTarget = evaluator.getSum(emitRate, curTime);
		var delta = hxd.Math.floor(emitTarget - emitCount);
		doEmit(delta);


		var i = instances.length;
		while (i-- > 0) {
			if(instances[i].life > lifeTime) {
				instances[i].remove();
			}
			else {
				instances[i].update(dt);
			}
		}
		lastTime = curTime;
		curTime += dt;
	}

	public function setTime(time: Float) {
		if(time < lastTime || lastTime < 0) {
			reset();
		}

		var catchup = time - curTime;
		var numTicks = hxd.Math.round(hxd.Timer.wantedFPS * catchup);
		for(i in 0...numTicks) {
			tick(catchup / numTicks);
		}

		// var deltaTime = time - lastTime;
		// lastTime = curTime;
		// curTime = time;

		// if(deltaTime <= 0.01)
		// 	return;
	}

	override function sync(ctx) {
		super.sync(ctx);
		// if(ctx.elapsedTime == 0)
		// 	return;

		// if(ctx.time < lastTime || lastTime < 0) {
		// 	reset();
		// }


		// for(inst in instances) {
		// 	inst.update(deltaTime);
		// }
	}
}


class Emitter extends Object3D {

	var emitRate = 50.0;
	var emitRateRandom = 2.0;

	public function new(?parent) {
		super(parent);
		props = { };
	}

	static var emitterParams : Array<ParamDef> = [
		{
			name: "lifeTime",
			t: PFloat(0, 10),
			def: 1.0,
			noanim: true
		},
		{
			name: "maxCount",
			t: PInt(0, 100),
			def: 20,
			noanim: true
		},
		{
			name: "emitRate",
			t: PInt(0, 100),
			def: 5
		},
		{
			name: "emitSize",
			t: PFloat(0, 10),
			def: 1.0
		},
	];

	static var instanceParams : Array<ParamDef> = [
		{
			name: "speed",
			t: PVec(3),
			def: [5.,0.,0.]
		},
		{
			name: "scale",
			t: PVec(3),
			def: [1.,1.,1.]
		}
	];

	static var PARAMS : Array<ParamDef> = {
		var a = emitterParams.copy();
		for(i in instanceParams)
			a.push(i);
		a;
	};

	override function save() {
		var obj : Dynamic = super.save();
		for(param in PARAMS) {
			if(Reflect.hasField(props, param.name)) {
				var f = Reflect.field(props, param.name);
				if(f != param.def) {
					Reflect.setField(obj, param.name, f);
				}
			}
		}
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		for(param in PARAMS) {
			if(Reflect.hasField(obj, param.name)) {
				Reflect.setField(props, param.name, Reflect.field(obj, param.name));
			}
		}
	}

	override function makeInstanceRec(ctx: Context) {
		ctx = makeInstance(ctx);
		// Don't make children, which are used to setup particles
	}

	static inline function randProp(name: String) {
		return name + "_rand";
	}

	function getParamVal(name: String, rand: Bool=false) : Dynamic {
		var param = PARAMS.find(p -> p.name == name);
		var isVector = switch(param.t) {
			case PVec(_): true;
			default: false;
		}
		var val : Dynamic = rand ? (isVector ? [0.,0.,0.,0.] : 0.) : param.def;
		if(rand)
			name = randProp(name);
		if(props != null && Reflect.hasField(props, name)) {
			val = Reflect.field(props, name);
		}
		if(isVector)
			return h3d.Vector.fromArray(val);
		return val;
	}

	public function applyParams(emitterObj: EmitterObject) {
		var randIdx = 0;
		var template = children[0];
		if(template == null)
			return;

		function makeVal(base: Float, curve: Curve, randFactor: Float, randCurve: Curve) {
			var val : Value = if(curve != null)
				VCurveValue(curve, base);
			else
				VConst(base);

			if(randFactor != 0.0) {
				var randScale = randCurve != null ? VCurveValue(randCurve, randFactor) : VConst(randFactor);
				val = VAdd(val, VNoise(randIdx++, randScale));
			}

			return val;
		}

		function makeParam(scope: Prefab, name: String) {
			inline function getCurve(name) {
				return scope.getOpt(Curve, name);
			}

			var param = PARAMS.find(p -> p.name == name);
			switch(param.t) {
				case PVec(_):
					var baseval : h3d.Vector = getParamVal(param.name);
					var randVal : h3d.Vector = getParamVal(param.name, true);
					return VVector(
						makeVal(baseval.x, getCurve(param.name + ".x"), randVal != null ? randVal.x : 0.0, getCurve(param.name + ".x.rand")),
						makeVal(baseval.y, getCurve(param.name + ".y"), randVal != null ? randVal.y : 0.0, getCurve(param.name + ".y.rand")),
						makeVal(baseval.z, getCurve(param.name + ".z"), randVal != null ? randVal.z : 0.0, getCurve(param.name + ".z.rand")));
				default:
					var baseval : Float = getParamVal(param.name);
					var randVal : Float = getParamVal(param.name, true);
					return makeVal(baseval, getCurve(param.name), randVal != null ? randVal : 0.0, getCurve(param.name + ".rand"));
			}
		}

		emitterObj.instDef = {
			localSpeed: makeParam(template, "speed"),
			localOffset: VConst(0.0),
			scale: VConst(1.0),
		};

		trace(emitterObj.instDef.localSpeed);
		emitterObj.particleTemplate = template;
		emitterObj.lifeTime = getParamVal("lifeTime");
		emitterObj.maxCount = getParamVal("maxCount");
		emitterObj.emitRate = makeParam(this, "emitRate");
		emitterObj.emitSize = makeParam(this, "emitSize");
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		// var randIdx = 0;
		// function makeVal(base: Float, curve: Curve, randFactor: Float, randCurve: Curve) {
		// 	var val : Value = if(curve != null)
		// 		VCurveValue(curve, base);
		// 	else
		// 		VConst(base);

		// 	if(randFactor != 0.0) {
		// 		var randScale = randCurve != null ? VCurveValue(randCurve, randFactor) : VConst(randFactor);
		// 		val = VAdd(val, VNoise(randIdx++, randScale));
		// 	}

		// 	return val;
		// }

		// var template = children[0];
		// if(template == null)
		// 	return ctx;


		// function makeParam(scope: Prefab, name: String) {
		// 	inline function getCurve(name) {
		// 		return scope.getOpt(Curve, name);
		// 	}

		// 	var param = PARAMS.find(p -> p.name == name);
		// 	switch(param.t) {
		// 		case PVec(_):
		// 			var baseval : h3d.Vector = getParamVal(param.name);
		// 			var randVal : h3d.Vector = getParamVal(param.name, true);
		// 			return VVector(
		// 				makeVal(baseval.x, getCurve(param.name + ".x"), randVal != null ? randVal.x : 0.0, getCurve(param.name + ".x.rand")),
		// 				makeVal(baseval.y, getCurve(param.name + ".y"), randVal != null ? randVal.y : 0.0, getCurve(param.name + ".y.rand")),
		// 				makeVal(baseval.z, getCurve(param.name + ".z"), randVal != null ? randVal.z : 0.0, getCurve(param.name + ".z.rand")));
		// 		default:
		// 			var baseval : Float = getParamVal(param.name);
		// 			var randVal : Float = getParamVal(param.name, true);
		// 			return makeVal(baseval, getCurve(param.name), randVal != null ? randVal : 0.0, getCurve(param.name + ".rand"));
		// 	}
		// }

		// var instDef : InstanceDef = {
		// 	localSpeed: makeParam(template, "speed"),
		// 	localOffset: VConst(0.0),
		// 	scale: VConst(1.0),
		// };

		var emitterObj = new EmitterObject(ctx.local3d);
		emitterObj.context = ctx;
		applyParams(emitterObj);
		// emitterObj.particleTemplate = children[0];
		// emitterObj.lifeTime = getParamVal("lifeTime");
		// emitterObj.maxCount = getParamVal("maxCount");
		// emitterObj.emitRate = makeParam(this, "emitRate");
		// emitterObj.emitSize = makeParam(this, "emitSize");
		ctx.local3d = emitterObj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor

		
		function refresh() {
			ctx.properties.clear();
			this.edit(ctx);
		}

		function onChange(pname: String) {
			ctx.onChange(this, pname);
			var emitter = Std.instance(ctx.getContext(this).local3d, EmitterObject);
			if(emitter != null)
				applyParams(emitter);
		}


		var emGroup = new Element('<div class="group" name="Emitter"></div>');
		// hide.comp.PropsEditor.makePropsList(emitter)
		// var lines : Array<String> = [];
		// var items : Array<hide.comp.PropsEditor.PropDef> = [];
		// for(p in emitterParams) {

		// 	items.push({name: p.name, t: p.y, def: p.def});
		// }	
		emGroup.append(hide.comp.PropsEditor.makePropsList(emitterParams));
		var props = ctx.properties.add(emGroup, this.props, onChange);


		{
			var instGroup = new Element('<div class="group" name="Particles"></div>');
			var dl = new Element('<dl>').appendTo(instGroup);
			for(p in instanceParams) {
				var dt = new Element('<dt>${p.name}</dt>').appendTo(dl);
				var dd = new Element('<dd>').appendTo(dl);
				if(Reflect.hasField(this.props, p.name)) {
					hide.comp.PropsEditor.makePropEl(p, dd);
				}
				else {
					var btn = new Element('<input type="button" value="+"></input>').appendTo(dd);
					btn.click(function(e) {
						Reflect.setField(this.props, p.name, p.def);
						refresh();
					});
				}
				var dt = new Element('<dt>~</dt>').appendTo(dl);
				var dd = new Element('<dd>').appendTo(dl);
				var randDef : Dynamic = switch(p.t) {
					case PVec(n): [for(i in 0...n) 0.0];
					case PFloat(_): 0.0;
					default: 0;
				};
				if(Reflect.hasField(this.props, randProp(p.name))) {
					hide.comp.PropsEditor.makePropEl({
						name: randProp(p.name),
						t: p.t,
						def: randDef}, dd);
				}
				else {
					var btn = new Element('<input type="button" value="+"></input>').appendTo(dd);
					btn.click(function(e) {
						Reflect.setField(this.props, randProp(p.name), randDef);
						refresh();
					});
				}
			}
			var props = ctx.properties.add(instGroup, this.props, onChange);
		}


		// var lines : Array<String> = [];
		// for(p in instanceParams) {
		// 	switch(p.type) {
		// 		case PFloat(min, max):
		// 			lines.push('<dt>${p.name}</dt><dd>
		// 				<input type="range" min="${min}" max="${max}" value="${p.def}" field="props.${p.name}"/>
		// 			</dd>');
		// 		case PInt(min, max):
		// 			lines.push('<dt>${p.name}</dt><dd>
		// 				<input type="range" min="${min}" max="${max}" value="${p.def}" field="props.${p.name}" step="1" />
		// 			</dd>');
		// 		default:
		// 	}
		// }
		// var props = ctx.properties.add(new hide.Element('<div class="group" name="Particles">' + lines.join('') + '</div>'),this, function(pname) {
		// 	ctx.onChange(this, pname);
		// });
		// // ctx.properties.addProps(items, this.props, function(pname) {
		// 	ctx.onChange(this, pname);
		// });
		#end
	}


	override function getHideProps() {
		return { icon : "asterisk", name : "Emitter", fileSource : null };
	}

	static var _ = Library.register("emitter", Emitter);

}