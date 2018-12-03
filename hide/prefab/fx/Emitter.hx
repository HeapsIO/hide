package hide.prefab.fx;
import hide.prefab.Curve;
import hide.prefab.fx.FX.ShaderAnimation;
using Lambda;

enum SimulationSpace {
	Local;
	World;
}

enum AlignMode {
	None;
	Screen;
	Axis;
}

enum EmitShape {
	Cone;
	Sphere;
	Box;
	Cylinder;
}

enum Orientation {
	Forward;
	Normal;
	Speed;
	Random;
}

typedef ParamDef = {
	> hide.prefab.Props.PropDef,
	?animate: Bool,
	?instance: Bool
}

typedef InstanceDef = {
	localSpeed: Value,
	worldSpeed: Value,
	localOffset: Value,
	scale: Value,
	stretch: Value,
	rotation: Value,
	color: Value,
}

typedef ShaderAnims = Array<ShaderAnimation>;

@:allow(hide.prefab.fx.EmitterObject)
private class ParticleInstance extends h3d.scene.Object {
	var emitter : EmitterObject;
	var evaluator : Evaluator;

	public var life = 0.0;

	public var curVelocity = new h3d.Vector();
	public var orientation = new h3d.Quat();

	public var def : InstanceDef;
	public var shaderAnims : ShaderAnims;
	public var baseMat : h3d.Matrix;
	var childMat = new h3d.Matrix();

	public function new(emitter: EmitterObject, def: InstanceDef) {
		switch(emitter.simulationSpace){
			// Particles in Local are spawned next to emitter in the scene tree,
			// so emitter shape can be transformed (especially scaled) without affecting children
			case Local : super(emitter.parent);
			case World : super(emitter.getScene());
		}
		this.def = def;
		this.emitter = emitter;
		this.evaluator = new Evaluator(emitter.random);
		emitter.instances.push(this);
	}

	public function update(dt : Float) {
		var child = getChildAt(0);
		if(child == null)
			return;

		var t = hxd.Math.clamp(life / emitter.lifeTime, 0.0, 1.0);

		var localSpeed = evaluator.getVector(def.localSpeed, t);
		if(localSpeed.length() > 0.001) {
			localSpeed.transform3x3(orientation.toMatrix());
		}
		var worldSpeed = evaluator.getVector(def.worldSpeed, t);
		if(emitter.simulationSpace == Local)
			worldSpeed.transform3x3(emitter.invTransform);

		curVelocity = localSpeed.add(worldSpeed);
		if(emitter.emitOrientation == Speed && curVelocity.lengthSq() > 0.01) {
			getRotationQuat().initDirection(curVelocity);
			posChanged = true;
		}

		x += curVelocity.x * dt;
		y += curVelocity.y * dt;
		z += curVelocity.z * dt;

		var rot = evaluator.getVector(def.rotation, t);
		rot.scale3(Math.PI / 180.0);
		var offset = evaluator.getVector(def.localOffset, t);
		var scaleVec = evaluator.getVector(def.stretch, t);
		scaleVec.scale3(evaluator.getFloat(def.scale, t));

		childMat.initScale(scaleVec.x, scaleVec.y, scaleVec.z);
		childMat.rotate(rot.x, rot.y, rot.z);
		childMat.translate(offset.x, offset.y, offset.z);
		if(baseMat != null)
			childMat.multiply(baseMat, childMat);
		child.setTransform(childMat);

		for(anim in shaderAnims) {
			anim.setTime(t);
		}

		var mesh = Std.instance(child, h3d.scene.Mesh);
		if(mesh != null && def.color != null) {
			var mat = mesh.material;
			switch(def.color) {
				case VCurve(a):
					mat.color.a = evaluator.getFloat(def.color, t);
				default:
					mat.color = evaluator.getVector(def.color, t);
			}
		}

		life += dt;
	}

	override function syncRec( ctx : h3d.scene.RenderContext ) {
		var child = getChildAt(0);
		if(child != null) {
			switch(emitter.alignMode) {
				case Screen: {
					var mat = ctx.camera.mcam.clone();
					mat.invert();
					switch(emitter.simulationSpace){
						case Local:mat.multiply3x4(mat, emitter.invTransform);
						case World:
					}
					var q = new h3d.Quat();
					q.initRotateMatrix(mat);
					setRotationQuat(q);
				}
				case Axis: {
					var absChildMat = new h3d.Matrix();
					absChildMat.multiply(getAbsPos(), childMat);
					var alignVec = emitter.alignAxis.clone();
					alignVec.transform3x3(absChildMat);
					alignVec.normalize();

					var rotAxis = emitter.alignLockAxis.clone();
					rotAxis.transform3x3(getAbsPos());
					rotAxis.normalize();

					var camVec : h3d.Vector = ctx.camera.pos.sub(absPos.getPosition());
					camVec.normalize();

				    var d = camVec.clone();
					d.scale3(camVec.dot3(rotAxis));
					d = camVec.sub(d);
					d.normalize();
					var angle = hxd.Math.acos(alignVec.dot3(d));
					var cross = alignVec.cross(d);
					if(rotAxis.dot3(cross) < 0)
						angle = -angle;

					var q = new h3d.Quat();
					q.initRotateAxis(emitter.alignLockAxis.x, emitter.alignLockAxis.y, emitter.alignLockAxis.z, angle);
					var cq = child.getRotationQuat();
					cq.multiply(cq, q);
					child.setRotationQuat(cq);
				}
				case None:
			}
		}
		super.syncRec(ctx);
	}

	function kill() {
		remove();
		emitter.instances.remove(this);
	}
}

@:allow(hide.prefab.fx.ParticleInstance)
@:allow(hide.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public var enable : Bool;
	public var particleVisibility(default, null) : Bool;

	public var particleTemplate : hide.prefab.Object3D;
	public var maxCount = 20;
	public var lifeTime = 2.0;
	public var emitShape : EmitShape = Cylinder;
	public var emitOrientation : Orientation = Forward;
	public var simulationSpace : SimulationSpace = Local;
	public var emitAngle : Float = 0.0;
	public var emitRad1 : Float = 1.0;
	public var emitRad2 : Float = 1.0;
	public var emitSurface : Bool = false;

	public var frameCount : Int = 0;
	public var frameDivisionX : Int = 1;
	public var frameDivisionY : Int = 1;
	public var animationRepeat : Float = 1;

	public var alignMode : AlignMode;
	public var alignAxis : h3d.Vector;
	public var alignLockAxis : h3d.Vector;

	public var emitRate : Value;

	public var instDef : InstanceDef;

	public var invTransform : h3d.Matrix;


	public function new(?parent) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
		evaluator = new Evaluator(random);
		reset();
	}

	var random: hxd.Rand;
	var randomSeed = 0;
	var context : hide.prefab.Context;
	var emitCount = 0;
	var lastTime = -1.0;
	var curTime = 0.0;
	var renderTime = 0.0;
	var evaluator : Evaluator;
	var instances : Array<ParticleInstance> = [];

	public function reset() {
		particleVisibility = true;
		enable = true;
		random.init(randomSeed);
		curTime = 0.0;
		lastTime = 0.0;
		emitCount = 0;
		for(inst in instances.copy()) {
			inst.kill();
		}
	}

	public function setParticleVibility( b : Bool ){
		for(inst in instances) {
			inst.visible = b;
		}
		particleVisibility = b;
	}

	function doEmit(count: Int) {
		if(count == 0)
			return;

		if(instDef == null || particleTemplate == null)
			return;

		var shapeAngle = hxd.Math.degToRad(emitAngle) / 2.0;

		var tmpq = new h3d.Quat();
		var offset = new h3d.Vector();
		var direction = new h3d.Vector();

		for(i in 0...count) {
			var part = new ParticleInstance(this, instDef);
			part.visible = particleVisibility;
			context.local3d = part;
			var ctx = particleTemplate.makeInstance(context);

			tmpq.identity();

			switch(emitShape) {
				case Box:
					offset.set(random.srand(0.5), random.srand(0.5), random.srand(0.5));
				case Cylinder:
					var dx = 0.0, dy = 0.0;
					if(emitSurface) {
						var a = random.srand(Math.PI);
						dx = Math.cos(a);
						dy = Math.sin(a);
					}
					else {
						do {
							dx = random.srand(1.0);
							dy = random.srand(1.0);
						}
						while(dx * dx + dy * dy > 1.0);
					}
					var x = random.rand();
					offset.set(x - 0.5, dx * 0.5, dy * 0.5);
					if(emitOrientation == Normal)
						tmpq.initRotation(0, -hxd.Math.atan2(dy, dx), Math.PI/2);
					offset.y *= hxd.Math.lerp(emitRad1, emitRad2, x);
					offset.z *= hxd.Math.lerp(emitRad1, emitRad2, x);
				case Sphere:
					do {
						offset.x = random.srand(1.0);
						offset.y = random.srand(1.0);
						offset.z = random.srand(1.0);
					}
					while(offset.lengthSq() > 1.0);
					if(emitSurface)
						offset.normalize();
					offset.scale3(0.5);
					if(emitOrientation == Normal)
						tmpq.initDirection(offset);
				case Cone:
					offset.set(0, 0, 0);
					var theta = random.rand() * Math.PI * 2;
					var phi = shapeAngle * random.rand();
					direction.x = Math.cos(phi) * scaleX;
					direction.y = Math.sin(phi) * Math.sin(theta) * scaleY;
					direction.z = Math.sin(phi) * Math.cos(theta) * scaleZ;
					direction.normalizeFast();
					tmpq.initDirection(direction);
			}

			if(emitOrientation == Random)
				tmpq.initRotation(hxd.Math.srand(Math.PI), hxd.Math.srand(Math.PI), hxd.Math.srand(Math.PI));

			switch(simulationSpace){
				case Local:
					var localQuat = getRotationQuat().clone();
					var localMat = getAbsPos().clone();
					var parentInvMat = parent.getAbsPos().clone();
					parentInvMat.invert();
					localMat.multiply(localMat, parentInvMat);
					offset.transform(localMat);
					part.setPosition(offset.x, offset.y, offset.z);
					part.baseMat = particleTemplate.getTransform();
					localQuat.multiply(localQuat, tmpq);
					part.setRotationQuat(localQuat);
					part.orientation = localQuat.clone();
				case World:
					var worldPos = localToGlobal(offset.clone());
					part.setPosition(worldPos.x, worldPos.y, worldPos.z);
					part.baseMat = particleTemplate.getTransform();
					var worldQuat = new h3d.Quat();
					worldQuat.initRotateMatrix(getAbsPos());
					tmpq.multiply(tmpq, worldQuat);
					part.setRotationQuat(tmpq);
					part.orientation = tmpq.clone();
			}

			// Setup mats.
			// Should we do this manually here or make a recursive makeInstance on the template?
			var materials = particleTemplate.getAll(hide.prefab.Material);
			for(mat in materials) {
				if(mat.enabled)
					mat.makeInstance(ctx);
			}

			// Animated textures animations
			{
				var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
				if(frameCount > 1) {
					var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
					if(mesh != null && mesh.material != null) {
						var pshader = new h3d.shader.AnimatedTexture(mesh.material.texture, frameDivisionX, frameDivisionY, frameCount, frameCount * animationRepeat / lifeTime);
						pshader.startTime = renderTime;
						if(animationRepeat == 0) {
							pshader.startFrame = random.random(frameCount);
						}
						mesh.material.mainPass.addShader(pshader);
					}
				}
			}

			// Setup shaders
			part.shaderAnims = [];
			var shaders = particleTemplate.getAll(hide.prefab.Shader);
			for(shader in shaders) {
				if(!shader.enabled)
					continue;
				var shCtx = shader.makeInstance(ctx);
				if(shCtx == null)
					continue;
				hide.prefab.fx.FX.getShaderAnims(ctx, shader, part.shaderAnims);
			}
		}
		context.local3d = this;
		emitCount += count;
	}

	function tick(dt: Float) {
		if(emitRate == null || emitRate == VZero)
			return;

		invTransform = parent.getAbsPos().clone();
		invTransform.invert();

		var emitTarget = evaluator.getSum(emitRate, curTime);
		var delta = hxd.Math.ceil(emitTarget - emitCount);
		if(enable)
			doEmit(delta);

		var i = instances.length;
		while (i-- > 0) {
			if(instances[i].life > lifeTime) {
				instances[i].kill();
			}
			else {
				instances[i].update(dt);
			}
		}
		lastTime = curTime;
		curTime += dt;
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		renderTime = ctx.time;
	}

	public function setRandSeed(seed: Int) {
		randomSeed = seed;
		reset();
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
	}
}


class Emitter extends Object3D {

	public function new(?parent) {
		super(parent);
		props = { };
		for(param in emitterParams) {
			if(param.def != null)
				resetParam(param);
		}
	}

	public static var emitterParams : Array<ParamDef> = [
		{ name: "simulationSpace", t: PEnum(SimulationSpace), def: SimulationSpace.Local, disp: "Simulation Space", },
		{ name: "emitRate", t: PInt(0, 100), def: 5, disp: "Rate", animate: true },
		{ name: "lifeTime", t: PFloat(0, 10), def: 1.0 },
		{ name: "maxCount", t: PInt(0, 100), def: 20, },
		{ name: "emitShape", t: PEnum(EmitShape), def: EmitShape.Sphere, disp: "Emit Shape", },
		{ name: "emitAngle", t: PFloat(0, 360.0), disp: "Angle", },
		{ name: "emitRad1", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 1", },
		{ name: "emitRad2", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 2", },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface" },

		{ name: "emitOrientation", t: PEnum(Orientation), def: Orientation.Forward, disp: "Orientation", },
		{ name: "alignMode", t: PEnum(AlignMode), def: AlignMode.None, disp: "Alignment" },
		{ name: "alignAxis", t: PVec(3, -1.0, 1.0), def: [0.,0.,0.], disp: "Axis" },
		{ name: "alignLockAxis", t: PVec(3, -1.0, 1.0), def: [0.,0.,0.], disp: "Lock Axis" },

		{ name: "frameCount", t: PInt(0), def: 0 },
		{ name: "frameDivisionX", t: PInt(1), def: 1 },
		{ name: "frameDivisionY", t: PInt(1), def: 1 },
		{ name: "animationRepeat", t: PFloat(0, 2.0), def: 1.0 },
	];

	public static var instanceParams : Array<ParamDef> = [
		{ name: "instSpeed",      t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Speed" },
		{ name: "instWorldSpeed", t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "World Speed" },
		{ name: "instScale",      t: PFloat(0, 2.0),    def: 1.,         disp: "Scale" },
		{ name: "instStretch",    t: PVec(3, 0.0, 2.0), def: [1.,1.,1.], disp: "Stretch" },
		{ name: "instRotation",   t: PVec(3, 0, 360),   def: [0.,0.,0.], disp: "Rotation" },
		{ name: "instOffset",     t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Offset" }
	];

	public static var PARAMS : Array<ParamDef> = {
		var a = emitterParams.copy();
		for(i in instanceParams) {
			i.instance = true;
			i.animate = true;
			a.push(i);
		}
		a;
	};

	override function save() {
		var obj : Dynamic = super.save();
		obj.props = Reflect.copy(props);
		for(param in PARAMS) {
			var f : Dynamic = Reflect.field(props, param.name);
			if(f != null && haxe.Json.stringify(f) != haxe.Json.stringify(param.def)) {
				var val : Dynamic = f;
				switch(param.t) {
					case PEnum(en):
						val = Type.enumConstructor(val);
					default:
				}
				Reflect.setField(obj.props, param.name, val);
			}
			else {
				Reflect.deleteField(obj.props, param.name);
			}
		}
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		for(param in emitterParams) {
			if(Reflect.hasField(obj.props, param.name)) {
				var val : Dynamic = Reflect.field(obj.props, param.name);
				switch(param.t) {
					case PEnum(en):
						val = Type.createEnum(en, val);
					default:
				}
				Reflect.setField(props, param.name, val);
			}
			else if(param.def != null)
				resetParam(param);
		}
	}

	override function makeInstanceRec(ctx: Context) {
		ctx = makeInstance(ctx);
		return ctx;
		// Don't make children, which are used to setup particles
	}

	static inline function randProp(name: String) {
		return name + "_rand";
	}

	function getParamVal(name: String, rand: Bool=false) : Dynamic {
		var param = PARAMS.find(p -> p.name == name);
		if(param == null)
			return Reflect.field(props, name);
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

	function resetParam(param: ParamDef) {
		var a = Std.instance(param.def, Array);
		if(a != null)
			Reflect.setField(props, param.name, a.copy());
		else
			Reflect.setField(props, param.name, param.def);
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var emitterObj = Std.instance(ctx.local3d, EmitterObject);

		var randIdx = 0;
		var template = children[0] != null ? children[0].to(Object3D) : null;

		function makeParam(scope: Prefab, name: String): Value {
			var getCurve = hide.prefab.Curve.getCurve.bind(scope);
			function makeCompVal(baseProp: Null<Float>, defVal: Float, randProp: Null<Float>, pname: String, suffix: String) : Value {
				var xVal : Value = VZero;
				var xCurve = getCurve(pname + suffix);
				if(xCurve != null)
					xVal = VCurveScale(xCurve, baseProp != null ? baseProp : 1.0);
				else if(baseProp != null)
					xVal = VConst(baseProp);
				else
					xVal = defVal == 0.0 ? VZero : VConst(defVal);

				var randCurve = getCurve(pname + suffix + ".rand");
				var randVal : Value = VZero;
				if(randCurve != null)
					randVal = VRandom(randIdx++, VCurveScale(randCurve, randProp != null ? randProp : 1.0));
				else if(randProp != null)
					randVal = VRandom(randIdx++, VConst(randProp));

				if(randVal == VZero)
					return xVal;
				if(xVal == VZero)
					return randVal;
				return VAdd(xVal, randVal);
			}

			var baseProp: Dynamic = Reflect.field(props, name);
			var randProp: Dynamic = Reflect.field(props, randProp(name));
			var param = PARAMS.find(p -> p.name == name);
			switch(param.t) {
				case PVec(_):
					inline function makeComp(idx, suffix) {
						return makeCompVal(
							baseProp != null ? (baseProp[idx] : Float) : null,
							param.def != null ? param.def[idx] : 0.0,
							randProp != null ? (randProp[idx] : Float) : null,
							param.name, suffix);
					}
					return VVector(
						makeComp(0, ".x"),
						makeComp(1, ".y"),
						makeComp(2, ".z"));
				default:
					return makeCompVal(baseProp, param.def != null ? param.def : 0.0, randProp, param.name, "");
			}
		}

		function makeColor(scope: Prefab, name: String) {
			var curves = hide.prefab.Curve.getCurves(scope, name);
			if(curves == null || curves.length == 0)
				return null;
			return hide.prefab.Curve.getColorValue(curves);
		}

		if(template != null) {
			emitterObj.instDef = {
				localSpeed: makeParam(this, "instSpeed"),
				worldSpeed: makeParam(this, "instWorldSpeed"),
				localOffset: makeParam(this, "instOffset"),
				scale: makeParam(this, "instScale"),
				stretch: makeParam(this, "instStretch"),
				rotation: makeParam(this, "instRotation"),
				color: makeColor(template, "color"),
			};

			emitterObj.particleTemplate = template;
		}

		emitterObj.simulationSpace = getParamVal("simulationSpace");
		emitterObj.lifeTime = getParamVal("lifeTime");
		emitterObj.maxCount = getParamVal("maxCount");
		emitterObj.emitRate = makeParam(this, "emitRate");
		emitterObj.emitShape = getParamVal("emitShape");
		emitterObj.emitOrientation = getParamVal("emitOrientation");
		emitterObj.emitAngle = getParamVal("emitAngle");
		emitterObj.emitRad1 = getParamVal("emitRad1");
		emitterObj.emitRad2 = getParamVal("emitRad2");
		emitterObj.emitSurface = getParamVal("emitSurface");
		emitterObj.alignMode = getParamVal("alignMode");
		emitterObj.alignAxis = getParamVal("alignAxis");
		emitterObj.alignLockAxis = getParamVal("alignLockAxis");
		emitterObj.frameCount = getParamVal("frameCount");
		emitterObj.frameDivisionX = getParamVal("frameDivisionX");
		emitterObj.frameDivisionY = getParamVal("frameDivisionY");
		emitterObj.animationRepeat = getParamVal("animationRepeat");

		#if editor
		if(propName == null || ["emitShape", "emitAngle", "emitRad1", "emitRad2"].indexOf(propName) >= 0)
			updateEmitShape(emitterObj);
		#end
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var emitterObj = new EmitterObject(ctx.local3d);
		emitterObj.context = ctx;
		ctx.local3d = emitterObj;
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function removeInstance(ctx:Context):Bool {
		return false;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		function refresh() {
			ctx.properties.clear();
			this.edit(ctx);
		}

		var angleProp = null;

		function onChange(?pname: String) {
			ctx.onChange(this, pname);

			if(pname == "emitShape" || pname == "alignMode")
				refresh();
		}

		var params = emitterParams.copy();
		inline function removeParam(pname: String) {
			params.remove(params.find(p -> p.name == pname));
		}

		var emitShape : EmitShape = getParamVal("emitShape");
		if(emitShape != Cone)
			removeParam("emitAngle");
		if(emitShape != Cylinder) {
			removeParam("emitRad1");
			removeParam("emitRad2");
		}

		var alignMode : AlignMode = getParamVal("alignMode");
		switch(alignMode) {
			case None | Screen:
				removeParam("alignAxis");
				removeParam("alignLockAxis");
			default:
		}

		// Emitter
		{
			var emGroup = new Element('<div class="group" name="Emitter"></div>');
			emGroup.append(hide.comp.PropsEditor.makePropsList(params));
			var props = ctx.properties.add(emGroup, this.props, onChange);
		}

		// Instances
		{
			var instGroup = new Element('<div class="group" name="Particles"></div>');
			var dl = new Element('<dl>').appendTo(instGroup);
			for(p in instanceParams) {
				var dt = new Element('<dt>${p.disp != null ? p.disp : p.name}</dt>').appendTo(dl);
				var dd = new Element('<dd>').appendTo(dl);

				function addUndo(pname: String) {
					ctx.properties.undo.change(Field(this.props, pname, Reflect.field(this.props, pname)), function() {
						if(Reflect.field(this.props, pname) == null)
							Reflect.deleteField(this.props, pname);
						refresh();
					});
				}

				if(Reflect.hasField(this.props, p.name)) {
					hide.comp.PropsEditor.makePropEl(p, dd);
					dt.contextmenu(function(e) {
						e.preventDefault();
						new hide.comp.ContextMenu([
							{ label : "Reset", click : function() {
								addUndo(p.name);
								resetParam(p);
								onChange();
								refresh();
							} },
							{ label : "Remove", click : function() {
								addUndo(p.name);
								Reflect.deleteField(this.props, p.name);
								onChange();
								refresh();
							} },
						]);
						return false;
					});
				}
				else {
					var btn = new Element('<input type="button" value="+"></input>').appendTo(dd);
					btn.click(function(e) {
						addUndo(p.name);
						resetParam(p);
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
					dt.contextmenu(function(e) {
						e.preventDefault();
						new hide.comp.ContextMenu([
							{ label : "Reset", click : function() {
								addUndo(randProp(p.name));
								Reflect.setField(this.props, randProp(p.name), randDef);
								onChange();
								refresh();
							} },
							{ label : "Remove", click : function() {
								addUndo(randProp(p.name));
								Reflect.deleteField(this.props, randProp(p.name));
								onChange();
								refresh();
							} },
						]);
						return false;
					});
				}
				else {
					var btn = new Element('<input type="button" value="+"></input>').appendTo(dd);
					btn.click(function(e) {
						addUndo(randProp(p.name));
						Reflect.setField(this.props, randProp(p.name), randDef);
						refresh();
					});
				}
			}
			var props = ctx.properties.add(instGroup, this.props, onChange);
		}
	}

	override function setSelected( ctx : Context, b : Bool ) {
		var emitterObj = Std.instance(ctx.local3d, EmitterObject);
		if(emitterObj == null)
			return;
		var debugShape : h3d.scene.Object = emitterObj.find(c -> if(c.name == "_highlight") c else null);
		if(debugShape != null)
			debugShape.visible = b;
	}

	function updateEmitShape(emitterObj: EmitterObject) {
		var debugShape : h3d.scene.Object = emitterObj.find(c -> if(c.name == "_highlight") c else null);
		if(debugShape == null) {
			debugShape = new h3d.scene.Object(emitterObj);
			debugShape.name = "_highlight";
			debugShape.visible = false;
		}

		for(i in 0...debugShape.numChildren)
			debugShape.removeChild(debugShape.getChildAt(i));

		inline function circle(npts, f) {
			for(i in 0...(npts+1)) {
				var c = hxd.Math.cos((i / npts) * hxd.Math.PI * 2.0);
				var s = hxd.Math.sin((i / npts) * hxd.Math.PI * 2.0);
				f(i, c, s);
			}
		}

		var mesh : h3d.scene.Mesh = null;
		switch(emitterObj.emitShape) {
			case Cylinder: {
				var rad1 = getParamVal("emitRad1") * 0.5;
				var rad2 = getParamVal("emitRad2") * 0.5;
				var g = new h3d.scene.Graphics(debugShape);
				g.lineStyle(1, 0xffffff);
				circle(32, function(i, c, s) {
					if(i == 0)
						g.moveTo(-0.5, c * rad1, s * rad1);
					else
						g.lineTo(-0.5, c * rad1, s * rad1);
				});
				circle(32, function(i, c, s) {
					if(i == 0)
						g.moveTo(0.5, c * rad2, s * rad2);
					else
						g.lineTo(0.5, c * rad2, s * rad2);
				});
				g.lineStyle(1, 0xffffff);
				circle(8, function(i, c, s) {
					g.moveTo(-0.5, c * rad1, s * rad1);
					g.lineTo(0.5, c * rad2, s * rad2);
				});
				g.ignoreCollide = true;
				mesh = g;
			}
			case Box: {
				mesh = new h3d.scene.Box(0xffffff, true, debugShape);
			}
			case Cone: {
				var g = new h3d.scene.Graphics(debugShape);
				var angle = hxd.Math.degToRad(getParamVal("emitAngle")) / 2.0;
				var rad = hxd.Math.sin(angle);
				var dist = hxd.Math.cos(angle);
				g.lineStyle(1, 0xffffff);
				circle(32, function(i, c, s) {
					if(i == 0)
						g.moveTo(dist, c * rad, s * rad);
					else
						g.lineTo(dist, c * rad, s * rad);
				});
				g.lineStyle(1, 0xffffff);
				circle(4, function(i, c, s) {
					g.moveTo(0, 0, 0);
					g.lineTo(dist, c * rad, s * rad);
				});
				g.ignoreCollide = true;
				mesh = g;
			}
			case Sphere:
				mesh = new h3d.scene.Sphere(0xffffff, 0.5, true, debugShape);
		}

		if(mesh != null) {
			var mat = mesh.material;
			mat.mainPass.setPassName("overlay");
			mat.shadows = false;
		}

		return debugShape;
	}

	override function getHideProps() : HideProps {
		return { icon : "asterisk", name : "Emitter", allowParent : function(p) return p.to(FX) != null || p.getParent(FX) != null };
	}
	#end

	static var _ = hxd.prefab.Library.register("emitter", Emitter);

}