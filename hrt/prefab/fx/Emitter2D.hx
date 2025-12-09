package hrt.prefab.fx;

import hrt.prefab.fx.Emitter;
import hrt.impl.Gradient;
import hrt.prefab.Curve;

using Lambda;

@:access(hrt.prefab.fx.Emitter2DObject)
class Particle2DInstance extends h2d.SpriteBatch.BatchElement {
	public var emitter : Emitter2DObject;

	public var idx : Int;
	public var lifeTime : Float;
	public var curLifeTime : Float;

	var initialAbsPos = new h2d.col.Matrix();
	var currentAbsPos = new h2d.col.Matrix();
	var speed : h2d.col.Point = new h2d.col.Point();

	public function new(t : h2d.Tile, e : Emitter2DObject) {
		super(t);
		this.emitter = e;
	}

	static var tmpSpeed = new h2d.col.Point();
	static var tmpVec = new h2d.col.Point();
	static var tmpMat = new h2d.col.Matrix();

	public function getEuler(d : h2d.col.Point) {
		var dot = new h2d.col.Point(1, 0).dot(d.normalized());
		if ((d.x >= 0 && d.y >= 0) || (d.x < 0 && d.y >= 0))
			return hxd.Math.acos(dot);
		else
			return -hxd.Math.acos(dot);
	}

	override function remove() {
		super.remove();
		emitter.particles.remove(this);
	}

	override function update(dt : Float) {
		super.update(dt);

		getInitialAbsPos(initialAbsPos, dt);
		getCurrentAbsPos(currentAbsPos, dt);

		var absPos = new h2d.col.Matrix();
		absPos.multiply(initialAbsPos, currentAbsPos);

		this.x = absPos.getPosition().x;
		this.y = absPos.getPosition().y;

		var d = new h2d.col.Point(1, 0);
		d.transform2x2(initialAbsPos);
		this.rotation = getEuler(d);

		this.scaleX = absPos.getScale().x;
		this.scaleY = absPos.getScale().y;

		curLifeTime += dt;
		if (curLifeTime >= lifeTime) {
			remove();
			return false;
		}

		return true;
	}

	function getInitialAbsPos(m : h2d.col.Matrix, dt : Float) {
		var def = emitter.instDef;
		var evaluator = @:privateAccess emitter.evaluator;
		var t = hxd.Math.clamp(curLifeTime / lifeTime);

		m.identity();

		// POSITION
		if (def.localOffset != VZero) {
			evaluator.getVector2(idx, def.localOffset, t, tmpVec);
			m.initTranslate(tmpVec.x, tmpVec.y);
		}

		// ROTATION
		if (def.rotation != VZero) {
			var r = evaluator.getFloat(idx, def.rotation, t) * Math.PI / 180.0;
			m.rotate(r);
		}

		// SCALE
		evaluator.getVector2(idx, def.stretch, t, tmpVec);
		tmpVec *= evaluator.getFloat(idx, def.scale, t);
		tmpVec *= evaluator.getFloat(idx, def.scaleOverTime, emitter.curTime);
		m.scale(tmpVec.x, tmpVec.y);
	}

	function getCurrentAbsPos(m : h2d.col.Matrix, dt : Float) {
		var def = emitter.instDef;
		var evaluator = @:privateAccess emitter.evaluator;
		var t = hxd.Math.clamp(curLifeTime / lifeTime);

		if (t == 0) {
			switch (emitter.emitShape) {
				case Circle:
					var radius = evaluator.getFloat(emitter.emitRadius, emitter.curTime);
					var startAngle = evaluator.getFloat(emitter.emitAngle1, emitter.curTime) * hxd.Math.PI / 180;
					var endAngle = evaluator.getFloat(emitter.emitAngle2, emitter.curTime) * hxd.Math.PI / 180;

					// normalize the angular span to [0, 2PI)
					var twoPI = Math.PI * 2;
					var a0 = startAngle % twoPI;
					if (a0 < 0) a0 += twoPI;
					var a1 = endAngle % twoPI;
					if (a1 < 0) a1 += twoPI;
					var delta = a1 - a0;
					if (delta <= 0) delta += twoPI; // handle wrap-around

					// pick random angle uniformly over the angular span
					var a = a0 + emitter.rand.rand() * delta;

					// pick radius so area is uniform: r = sqrt(u*(R^2 - r0^2) + r0^2)
					var rsq = emitter.rand.rand() * Math.max(0, radius) * Math.max(0, radius);
					var r = emitter.emitSurface ? radius : Math.sqrt(rsq);

					var posX = r * Math.cos(a);
					var posY = r * Math.sin(a);
					if (emitter.emitOrientation.match(Normal))
						currentAbsPos.initRotate(getEuler(new h2d.col.Point(posX, posY)));

					currentAbsPos.translate(posX, posY);

				case Rectangle:
					var width = evaluator.getFloat(emitter.emitWidth, emitter.curTime);
					var height = evaluator.getFloat(emitter.emitHeight, emitter.curTime);

					var posX = (emitter.rand.rand() - 0.5) * width;
					var posY = (emitter.rand.rand() - 0.5) * height;
					if (emitter.emitSurface) {
						if (emitter.rand.rand() < 0.5)
							posX = emitter.rand.rand() < 0.5 ? -width / 2 : width / 2;
						else
							posY = emitter.rand.rand() < 0.5 ? -height / 2 : height / 2;
					}

					if (emitter.emitOrientation.match(Normal))
						currentAbsPos.initRotate(getEuler(new h2d.col.Point(posX, posY)));

					currentAbsPos.translate(posX, posY);
			}

			// if (simulationSpace.match(World)) {
			// 	var pos = getAbsPos().getPosition();
			// 	part.x += pos.x;
			// 	part.y += pos.y;
			// }

			// START LOCAL SPEED
			evaluator.getVector2(idx, emitter.startSpeed, emitter.curTime, tmpVec);
			tmpVec.transform2x2(currentAbsPos);
			speed += tmpVec;

			// START WORLD SPEED
			evaluator.getVector2(idx, emitter.startWorldSpeed, emitter.curTime, tmpVec);
			tmpVec.transform2x2(emitter.invTransform);
			speed += tmpVec;
		}

		// ACCELERATION
		if (def.acceleration != VZero) {
			evaluator.getVector2(idx, def.acceleration, t, tmpVec);
			tmpVec.scale(dt);
			tmpVec.transform2x2(currentAbsPos);
			speed += tmpVec;
		}

		// WORLD ACCELERATION
		if (def.worldAcceleration != VZero) {
			evaluator.getVector2(idx, def.worldAcceleration, t, tmpVec);
			tmpVec.scale(dt);
			if (emitter.simulationSpace == Local)
				tmpVec.transform2x2(emitter.invTransform);
			speed += tmpVec;
		}

		tmpSpeed.set(speed.x, speed.y);

		// SPEED
		if (def.localSpeed != VZero) {
			evaluator.getVector2(idx, def.localSpeed, t, tmpVec);
			tmpVec.transform2x2(currentAbsPos);
			tmpSpeed += tmpVec;
		}

		// DAMPEN
		if (def.dampen != VZero) {
			var dampen = evaluator.getFloat(idx, def.dampen, t);
			var scale = Math.exp(dampen* -dt);
			speed.scale(scale);
		}


		// WORLD SPEED
		if (def.worldSpeed != VZero) {
			evaluator.getVector2(idx, def.worldSpeed, t, tmpVec);
			if (emitter.simulationSpace == Local)
				tmpVec.transform2x2(emitter.invTransform);
			tmpSpeed += tmpVec;
		}

		// MAX VELOCITY
		if (def.maxVelocity != VZero) {
			var maxVel = evaluator.getFloat(idx, def.maxVelocity, t);
			var curVelSq = tmpSpeed.lengthSq();
			if (maxVel * maxVel < curVelSq) {
				tmpSpeed.normalize();
				tmpSpeed.scale(maxVel);
			}
		}

		// if (emitter.simulationSpace == World) {
		// 	tmpSpeed.x *= emitter.worldScale.x;
		// 	tmpSpeed.y *= emitter.worldScale.y;
		// }

		// STRETCH VELOCITY
		if (def.stretchVelocity != VZero) {
			// var s = evaluator.getFloat(idx, def.stretchVelocity, t);
			// var up = tmpCamVec2;
			// up.set(absPos._11, absPos._12, absPos._13);
			// var sx = hxd.Math.abs(tmpSpeed.dot(up));
			// sx = hxd.Math.min(sx, 0.25);

			// absPos._11 *= s * sx;
			// absPos._12 *= s * sx;
			// absPos._13 *= s * sx;
			// absPos._21 *= s * 1.0/sx;
			// absPos._22 *= s * 1.0/sx;
			// absPos._23 *= s * 1.0/sx;
			// absPos._31 *= s * 1.0/sx;
			// absPos._32 *= s * 1.0/sx;
			// absPos._33 *= s * 1.0/sx;
		}

		currentAbsPos.translate(tmpSpeed.x * dt, tmpSpeed.y * dt);

		if (def.orbitSpeed != VZero) {
			var orbitSpeed = evaluator.getFloat(idx, def.orbitSpeed, t);

			var factorOverTime = evaluator.getFloat(idx, def.orbitSpeedOverTime, emitter.curTime);
			orbitSpeed *= factorOverTime;

			var prevPos = currentAbsPos.getPosition().clone();
			tmpMat.initRotate(orbitSpeed * dt);
			tmpMat.multiply(currentAbsPos, tmpMat);
			var delta = tmpMat.getPosition().sub(prevPos);
			currentAbsPos.prependTranslate(delta.x, delta.y);

			// Take transform into account into local speed
			delta.scale(1 / dt);
			tmpSpeed.x += delta.x;
			tmpSpeed.y += delta.y;
		}

		if (emitter.emitOrientation.match(Speed) && hxd.Math.abs(tmpSpeed.length()) > 0.0001) {
			var targetRotation = getEuler(tmpSpeed);
			initialAbsPos.rotate(targetRotation);
		}
	}
}

enum Emit2DShape {
	Circle;
	Rectangle;
}

class Emitter2DObject extends h2d.Object {
	public var particles : Array<Particle2DInstance> = [];
	public var batch : h2d.SpriteBatch;
	var evaluator : Evaluator;
	var rand : hxd.Rand;

	var prevTime : Float;
	var curTime = 0.;
	var countToEmit = 0.;
	var lastEmitTime = 0.;
	var totalBurstCount = 0;
	var randomValues : Array<Float>;
	var randSlots : Int;
	var instanceCounter = 0;

	// Emitter parameters
	public var instDef : InstanceDef;
	public var texture : String;
	public var seed = 0;
	public var particleTemplate : hrt.prefab.Object3D;
	public var subEmitterTemplates : Array<Emitter>;
	public var subEmitters : Array<EmitterObject>;
	public var subEmitterKind : SubEmitterKind;
	public var trails : hrt.prefab.l3d.Trails.TrailObj;
	public var trailsTemplate : hrt.prefab.l3d.Trails;
	public var lifeTime = 2.0;
	public var lifeTimeRand = 0.0;
	public var speedFactor = 1.0;
	public var warmUpTime = 0.0;
	public var delay = 0.0;
	public var emitOrientation : Orientation = Forward;
	public var simulationSpace : SimulationSpace = Local;
	public var emitType : EmitType = Infinity;
	public var burstCount : Int = 1;
	public var burstParticleCount : Value;
	public var burstDelay : Float = 1.0;
	public var emitDuration : Float = 1.0;
	public var emitRate : Value;
	public var emitRateMin : Value;
	public var emitRateMax : Value;
	public var emitRateChangeDelay : Float = 1.0;
	public var emitRateChangeDelayStart : Float = 0.0;
	public var emitRateCurrent : Float = Math.NaN;
	public var emitRatePrevious : Float = Math.NaN;
	public var emitRateTarget : Float = Math.NaN;
	public var emitScale : Float = 1.0;
	public var maxCount = 20;
	public var startSpeed: Value;
	public var startWorldSpeed: Value;
	public var emitShape : Emit2DShape = Circle;
	public var emitRadius : Value;
	public var emitAngle1 : Value;
	public var emitAngle2 : Value;
	public var emitWidth : Value;
	public var emitHeight : Value;
	public var emitSurface : Bool = false;
	public var spriteSheet : String;
	public var frameCount : Int = 0;
	public var frameDivisionX : Int = 1;
	public var frameDivisionY : Int = 1;
	public var animationSpeed : Float = 1;
	public var animationLoop : Bool = true;
	public var animationUseSourceUVs : Bool = true;
	public var animationBlendBetweenFrames : Bool = true;
	public var useRandomColor : Bool = false;
	public var useRandomGradient : Bool = false;
	public var randomColor1 : h3d.Vector;
	public var randomColor2 : h3d.Vector;
	public var randomGradient : GradientData;
	public var invTransform = new h2d.col.Matrix();
	public var screenRot = new h3d.Matrix();
	public var worldScale = new h3d.Vector(1,1,1);

	public function new(?parent) {
		super(parent);

		batch = new h2d.SpriteBatch(getTile(), this);
		batch.hasRotationScale = true;
		evaluator = new Evaluator([0], 1);
		rand = new hxd.Rand(seed);
	}

	public function init(randSlots: Int, prefab: Emitter2D) {
		var randomValues = [for(_ in 0...(maxCount * randSlots)) rand.srand()];
		evaluator = new Evaluator(randomValues, randSlots);
	}

	public function setTime(time : Float) {
		prevTime = curTime;
		curTime = (time + warmUpTime) - delay;

		if (curTime < 0) {
			if (prevTime > 0)
				reset();
			return;
		}

		var dt = curTime - prevTime;
		if (dt < 0 || dt > hxd.Timer.maxDeltaTime) {
			reset();
			var targetTime = curTime;
			curTime = 0;
			prevTime = 0;
			var t = 0.;
			while (curTime < targetTime) {
				t = hxd.Math.min(t + hxd.Timer.dt, targetTime);
				setTime(t);
			}
		}
		else if (dt > 0) {
			tick(dt);
		}
	}

	function tick(dt : Float) {
		switch (emitType) {
			case Infinity:
				var emitTarget = evaluator.getFloat(emitRate, curTime) * hxd.Math.clamp(emitScale) * dt;
				countToEmit += hxd.Math.min(maxCount - particles.length, emitTarget);
				var t = hxd.Math.floor(countToEmit);
				countToEmit -= t;
				doEmit(t);

			case InfinityRandom:
				// TODO

			case Duration:
				var emitTarget = evaluator.getFloat(emitRate, curTime) * hxd.Math.clamp(emitScale) * dt;
				countToEmit += curTime >= emitDuration ? 0 : hxd.Math.min(maxCount - particles.length, emitTarget);
				var t = hxd.Math.floor(countToEmit);
				countToEmit -= t;
				doEmit(t);

			case Burst:
				if (burstDelay > 0) {
					var burstTarget = hxd.Math.min(burstCount, 1 + hxd.Math.floor(curTime / burstDelay));
					while (totalBurstCount < burstTarget) {
						var emitTarget = hxd.Math.ceil(hxd.Math.min(maxCount - particles.length, Std.int(evaluator.getFloat(burstParticleCount, curTime))));
						doEmit(emitTarget);
						totalBurstCount++;
					}
				}

			case BurstDuration:
				if (curTime < emitDuration) {
					var emitTarget = hxd.Math.ceil(hxd.Math.min(maxCount - particles.length, Std.int(evaluator.getFloat(burstParticleCount, curTime))));
					doEmit(emitTarget);
				}
		}

		invTransform.inverse(getAbsPos());

		// Update particles
		for (p in particles)
			@:privateAccess p.update(dt);

		// Draw particles
		if (batch == null)
			return;

		batch.clear();
		for (p in particles)
			batch.add(p);
	}

	function doEmit(count : Int) {
		for (_ in 0...count) {
			var part = new Particle2DInstance(getTile(), this);
			part.lifeTime = lifeTime + rand.srand(lifeTimeRand);
			part.idx = instanceCounter;
			this.particles.push(part);
			instanceCounter = (instanceCounter + 1) % maxCount;
		}
	}

	function reset() {
		particles = [];
		batch.clear();
		countToEmit = 0;
		totalBurstCount = 0;
		instanceCounter = 0;

		rand.init(seed);
		if (randomValues != null) {
			for(i in 0...randomValues.length)
				randomValues[i] = rand.srand();
		}
	}

	function getTile() {
		var t = h2d.Tile.fromColor(0xFFFFFF, 10, 10);
		if (texture != null)
			t = h2d.Tile.fromTexture(hxd.res.Loader.currentInstance.load(texture).toTexture());
		t.dx = -t.width / 2;
		t.dy = -t.height / 2;
		return t;
	}
}

@:access(hrt.prefab.fx.Emitter2DObject)
class Emitter2D extends Object2D {

	public static var emitterParams : Array<hrt.prefab.fx.Emitter.ParamDef> = [
		{ name: "texture", t: PTexture, def: 1.0, groupName : "Display" },

		{ name: "lifeTime", t: PFloat(0, 10), def: 1.0, groupName : "Properties" },
		{ name: "lifeTimeRand", t: PFloat(0, 1), def: 0.0, groupName : "Properties" },
		{ name: "subEmitterKind", disp: "Sub Kind", t: PEnum(SubEmitterKind), def: SubEmitterKind.SpawnOnDeath, groupName: "Properties"},
		{ name: "speedFactor", disp: "Speed Factor", t: PFloat(0, 1), def: 1.0, groupName : "Properties" },
		{ name: "warmUpTime", disp: "Warm Up", t: PFloat(0, 1), def: 0.0, groupName : "Properties" },
		{ name: "delay", disp: "Delay", t: PFloat(0, 10), def: 0.0, groupName : "Properties" },
		{ name: "seed", t: PInt(0, 100), def: 0, groupName : "Properties", disp: "Seed"},
		{ name: "simulationSpace", t: PEnum(SimulationSpace), def: SimulationSpace.Local, disp: "Simulation Space", groupName : "Properties" },

		// EMIT PARAMS
		{ name: "emitType", t: PEnum(EmitType), def: EmitType.Infinity, disp: "Type", groupName : "Emit Params"  },
		{ name: "emitDuration", t: PFloat(0, 10.0), disp: "Duration", def : 1.0, groupName : "Emit Params" },
		{ name: "emitRate", t: PInt(0, 100), def: 5, disp: "Rate", animate: true, groupName : "Emit Params" },
		{ name: "emitRateMin", t: PInt(0, 100), def: 5, disp: "Rate Min", animate: true, groupName : "Emit Params" },
		{ name: "emitRateMax", t: PInt(0, 100), def: 5, disp: "Rate Max", animate: true, groupName : "Emit Params" },
		{ name: "emitRateChangeDelay", t: PFloat(0.01, 5.0), def: 1.0, disp: "Rate Change Time", groupName : "Emit Params" },
		{ name: "burstCount", t: PInt(1, 10), disp: "Count", def : 1, groupName : "Emit Params" },
		{ name: "burstDelay", t: PFloat(0, 1.0), disp: "Delay", def : 1.0, groupName : "Emit Params" },
		{ name: "burstParticleCount", t: PInt(1, 10), disp: "Particle Count", def : 1, groupName : "Emit Params", animate: true },
		{ name: "maxCount", t: PInt(0, 100), def: 20, groupName : "Emit Params" },
		// EMIT SHAPE
		{ name: "emitShape", t: PEnum(Emit2DShape), def: Emit2DShape.Circle, disp: "Shape", groupName : "Emit Shape" },
		{ name: "emitRadius", t: PFloat(0, 360.0), def: 20.0, disp: "Radius", groupName : "Emit Shape", animate: true },
		{ name: "emitAngle1", t: PFloat(0, 360.0), def: 20.0, disp: "Angle 1", groupName : "Emit Shape", animate: true },
		{ name: "emitAngle2", t: PFloat(0, 360.0), def: 40.0, disp: "Angle 2", groupName : "Emit Shape", animate: true },
		{ name: "emitWidth", t: PFloat(0, 10.0), def: 1.0, disp: "Width", groupName : "Emit Shape", animate: true },
		{ name: "emitHeight", t: PFloat(0, 10.0), def: 1.0, disp: "Height", groupName : "Emit Shape", animate: true },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface", groupName : "Emit Shape" },
		{ name: "emitOrientation", t: PEnum(Orientation), def: Orientation.Forward, disp: "Orientation", groupName : "Emit Params" },
		// COLOR
		{ name: "useRandomColor", t: PBool, def: false, disp: "Random Color", groupName : "Color" },
		{ name: "useRandomGradient", t: PBool, def: false, disp: "Random Gradient", groupName : "Color" },
		{ name: "randomColor1", t: PVec(4), disp: "Color 1", def : [0,0,0,1], groupName : "Color" },
		{ name: "randomColor2", t: PVec(4), disp: "Color 2", def : [1,1,1,1], groupName : "Color" },
		{ name: "randomGradient", t:PGradient, disp: "Gradient", def: null, groupName : "Color" },
		// ANIMATION
		{ name: "spriteSheet", t: PFile(["jpg","png"]), def: null, groupName : "Sprite Sheet Animation", disp: "Sheet" },
		{ name: "frameCount", t: PInt(0), def: 0, groupName : "Sprite Sheet Animation", disp: "Frames" },
		{ name: "frameDivisionX", t: PInt(1), def: 1, groupName : "Sprite Sheet Animation", disp: "Divisions X" },
		{ name: "frameDivisionY", t: PInt(1), def: 1, groupName : "Sprite Sheet Animation", disp: "Divisions Y" },
		{ name: "animationSpeed", t: PFloat(0, 2.0), def: 1.0, groupName : "Sprite Sheet Animation", disp: "Speed" },
		{ name: "animationLoop", t: PBool, def: true, groupName : "Sprite Sheet Animation", disp: "Loop" },
		{ name: "animationUseSourceUVs", t: PBool, def: true, groupName : "Sprite Sheet Animation", disp: "Use Source UV" },
		{ name: "animationBlendBetweenFrames", t: PBool, def: true, groupName : "Sprite Sheet Animation", disp: "Blend frames" },

		// DEBUG
		{ name: "viewDebug", disp: "Show Debug",t: PBool, def: false, groupName : "Debug"},
	];

	public static var instanceParams : Array<hrt.prefab.fx.Emitter.ParamDef> = [
		{ name: "instAcceleration",			t: PVec(2, -10, 10),  def: [0.,0.], disp: "Acceleration", groupName: "Particle Movement"},
		{ name: "instWorldAcceleration",	t: PVec(2, -10, 10),  def: [0.,0.], disp: "World Acceleration", groupName: "Particle Movement"},
		{ name: "instSpeed",      			t: PVec(2, -10, 10),  def: [0.,0.], disp: "Fixed Speed", groupName: "Particle Movement" },
		{ name: "instWorldSpeed", 			t: PVec(2, -10, 10),  def: [0.,0.], disp: "Fixed World Speed", groupName: "Particle Movement"},

		// In instance param to avoid refactoring the param editor more, but this is no longer linked to the instances (hence the instance: false in the declaration)
		{ name: "instStartSpeed",      		t: PVec(2, -10, 10),  def: [0.,0.], disp: "Start Speed",			groupName: "Particle Movement", instance: false},
		{ name: "instStartWorldSpeed", 		t: PVec(2, -10, 10),  def: [0.,0.], disp: "Start World Speed",	groupName: "Particle Movement", instance: false},

		{ name: "instOrbitSpeed", 			t: PFloat(-10., 10.),  def: 0., disp: "Orbit Speed", groupName: "Particle Movement"},
		{ name: "instOrbitSpeedOverTime", 			t: PFloat(0, 2.0),  def: 1., disp: "Orbit Speed over time", groupName: "Particle Movement"},
		{ name: "instMaxVelocity",      			t: PFloat(0, 10.0),    def: 0.,         disp: "Max Velocity", groupName: "Limit Velocity"},
		{ name: "instDampen",      			t: PFloat(0, 10.0),    def: 0.,         disp: "Dampen", groupName: "Limit Velocity"},
		{ name: "instScale",      			t: PFloat(0, 2.0),    def: 1.,         disp: "Scale", groupName: "Particle Transform"},
		{ name: "instScaleOverTime",      			t: PFloat(0, 2.0),    def: 1.,         disp: "Scale over time", groupName: "Particle Transform"},
		{ name: "instStretch",    			t: PVec(2, 0.0, 2.0), def: [1.,1.], disp: "Stretch", groupName: "Particle Transform"},
		{ name: "instStretchVelocity",    	t: PFloat(0.0, 2.0), def: 0.0, disp: "Stretch Vel.", groupName: "Particle Transform"},
		{ name: "instRotation",   			t: PFloat(0, 360),   def: 0., disp: "Rotation", groupName: "Particle Transform"},
		{ name: "instOffset",     			t: PVec(2, -10, 10),  def: [0.,0.], disp: "Offset", groupName: "Particle Transform"},
	];

	public static var PARAMS : Map<String, ParamDef> = {
		var map = new Map();
		for(e in emitterParams) {
			map.set(e.name, e);
		}
		for(i in instanceParams) {
			i.instance = i.instance ?? true;
			i.animate = true;
			map.set(i.name, i);
		}
		map;
	};

	#if editor
	var graphics : h2d.Graphics;
	#end

	public function new(parent, shared: ContextShared) {
		super(parent, shared);

		props = { };
		for(param in emitterParams) {
			if(param.def != null)
				resetParam(param);
		}
	}

	override function makeObject(parent2d : h2d.Object) {
		return new Emitter2DObject(parent2d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var emitterObj = Std.downcast(local2d, Emitter2DObject);

		var randIdx = 0;

		function makeParam(scope: Prefab, name: String): Value {
			var getCurve = hrt.prefab.Curve.getCurve.bind(scope);

			function vVal(f: Float) : Value {
				return switch(f) {
					case 0.0: VZero;
					case 1.0: VOne;
					default: VConst(f);
				}
			}

			function vMult(a: Value, b: Value) : Value {
				if(a == VZero || b == VZero) return VZero;
				if(a == VOne) return b;
				if(b == VOne) return a;
				switch a {
					case VConst(va):
						return VMult(a, b);
					case VCurve(ca):
						return VMult(a, b);
					case VRandomScale(ri,rscale):
						switch b {
							case VCurve(vb): return VAddRandCurve(0, ri, rscale, vb);
							default:
						}
					case VAdd(va,VRandomScale(ri,rscale)):
						var av = switch (va) {
							case VConst(v): v;
							case VOne: 1.0;
							default: throw "Unsupported";
						}
						switch b {
							case VCurve(vb): return VAddRandCurve(av, ri, rscale, vb);
							default:
						}
					default:
				}
				return VMult(a, b);
			}

			function vAdd(a: Value, b: Value) : Value {
				if(a == VZero) return b;
				if(b == VZero) return a;
				switch a {
					case VConst(va):
						switch b {
							case VConst(vb): return VConst(va + vb);
							default:
						}
					default:
				}
				return VAdd(a, b);
			}

			function makeCompVal(baseProp: Null<Float>, defVal: Float, randProp: Null<Float>, pname: String, suffix: String) : Value {
				var xVal = vVal(baseProp != null ? baseProp : defVal);
				var randCurve = getCurve(pname + suffix + ":rand");
				var randVal : Value = VZero;
				if(randCurve != null)
					randVal = VRandom(randIdx++, VMult(randCurve.makeVal(), VConst(randProp != null ? randProp : 1.0)));
				else if(randProp != null && randProp != 0.0)
					randVal = VRandomScale(randIdx++, randProp);

				var xCurve = getCurve(pname + suffix);
				if (xCurve != null) {
					if (xCurve.blendMode == CurveBlendMode.RandomBlend) {
						return VRandomBetweenCurves(randIdx++, xCurve);
					}
					else {
						if (pname.indexOf("Rotation") >= 0 || pname.indexOf("Offset") >= 0)
							return vAdd(vAdd(xVal, randVal), xCurve.makeVal());
						else
							return vMult(vAdd(xVal, randVal), xCurve.makeVal());
					}
				}
				else
					return vAdd(xVal, randVal);
			}

			var baseProp: Dynamic = Reflect.field(props, name);
			var randProp: Dynamic = Reflect.field(props, randProp(name));
			var param = PARAMS.get(name);
			switch(param.t) {
				case PVec(_):
					inline function makeComp(idx, suffix) {
						return makeCompVal(
							baseProp != null ? (baseProp[idx] : Float) : null,
							param.def != null ? param.def[idx] : 0.0,
							randProp != null ? (randProp[idx] : Float) : null,
							param.name, suffix);
					}
					var v : Value = VVector(
						makeComp(0, ":x"),
						makeComp(1, ":y"),
						makeComp(2, ":z"));
					if(v.match(VVector(VZero, VZero, VZero)))
						v = VZero;
					else if(v.match(VVector(VOne, VOne, VOne)))
						v = VOne;
					return v;

				default:
					return makeCompVal(baseProp, param.def != null ? param.def : 0.0, randProp, param.name, "");
			}
		}

		function makeColor(scope: Prefab, name: String) {
			var curves = hrt.prefab.Curve.getCurves(scope, name);
			if(curves == null || curves.length == 0)
				return null;
			return hrt.prefab.Curve.getColorValue(curves);
		}

		var d = new InstanceDef();
		d.localSpeed = makeParam(this, "instSpeed");
		d.worldSpeed = makeParam(this, "instWorldSpeed");
		d.orbitSpeed = makeParam(this, "instOrbitSpeed");
		d.orbitSpeedOverTime = makeParam(this, "instOrbitSpeedOverTime");
		d.acceleration = makeParam(this, "instAcceleration");
		d.worldAcceleration = makeParam(this, "instWorldAcceleration");
		d.localOffset = makeParam(this, "instOffset");
		d.scale = makeParam(this, "instScale");
		d.scaleOverTime = makeParam(this, "instScaleOverTime");
		d.dampen = makeParam(this, "instDampen");
		d.maxVelocity = makeParam(this, "instMaxVelocity");
		d.stretch = makeParam(this, "instStretch");
		d.stretchVelocity = makeParam(this, "instStretchVelocity");
		d.rotation = makeParam(this, "instRotation");
		emitterObj.instDef = d;

		// DISPLAY
		emitterObj.texture 			= 	getParamVal("texture");

		// RANDOM
		emitterObj.seed 			= 	getParamVal("seed");
		emitterObj.subEmitterKind		= 	getParamVal("subEmitterKind");
		// LIFE
		emitterObj.lifeTime 			= 	getParamVal("lifeTime");
		emitterObj.lifeTimeRand 		= 	getParamVal("lifeTimeRand");
		emitterObj.speedFactor 			= 	getParamVal("speedFactor");
		emitterObj.warmUpTime 			= 	getParamVal("warmUpTime");
		emitterObj.delay 				= 	getParamVal("delay");
		// EMIT PARAMS
		emitterObj.emitType 			= 	getParamVal("emitType");
		emitterObj.burstCount 			= 	getParamVal("burstCount");
		emitterObj.burstDelay 			= 	getParamVal("burstDelay");
		emitterObj.burstParticleCount 	= 	makeParam(this, "burstParticleCount");
		emitterObj.emitDuration 		= 	getParamVal("emitDuration");
		emitterObj.simulationSpace 		= 	getParamVal("simulationSpace");
		emitterObj.emitOrientation 		= 	getParamVal("emitOrientation");
		emitterObj.maxCount 			= 	getParamVal("maxCount");
		emitterObj.emitRate 			= 	makeParam(this, "emitRate");
		emitterObj.emitRateMin 			= 	makeParam(this, "emitRateMin");
		emitterObj.emitRateMax 			= 	makeParam(this, "emitRateMax");
		emitterObj.emitRateChangeDelay 	= 	getParamVal("emitRateChangeDelay");
		emitterObj.emitShape 			= 	getParamVal("emitShape");
		// EMIT SHAPE
		emitterObj.emitRadius 			= 	makeParam(this, "emitRadius");
		emitterObj.emitAngle1 			= 	makeParam(this, "emitAngle1");
		emitterObj.emitAngle2 			= 	makeParam(this, "emitAngle2");
		emitterObj.emitWidth 			= 	makeParam(this, "emitWidth");
		emitterObj.emitHeight 			= 	makeParam(this, "emitHeight");
		emitterObj.emitSurface 			= 	getParamVal("emitSurface");
		// ANIMATION
		emitterObj.spriteSheet 			= 	getParamVal("spriteSheet");
		emitterObj.frameCount 			= 	getParamVal("frameCount");
		emitterObj.frameDivisionX 		= 	getParamVal("frameDivisionX");
		emitterObj.frameDivisionY 		= 	getParamVal("frameDivisionY");
		emitterObj.animationSpeed 		= 	getParamVal("animationSpeed");
		emitterObj.animationLoop 		= 	getParamVal("animationLoop");
		emitterObj.animationUseSourceUVs 			= 	getParamVal("animationUseSourceUVs");
		emitterObj.animationBlendBetweenFrames 		= 	getParamVal("animationBlendBetweenFrames");

		// RANDOM COLOR
		emitterObj.useRandomColor 		= 	getParamVal("useRandomColor");
		emitterObj.useRandomGradient 	= 	getParamVal("useRandomGradient");
		emitterObj.randomColor1 		= 	getParamVal("randomColor1");
		emitterObj.randomColor2 		= 	getParamVal("randomColor2");
		emitterObj.randomGradient 		= 	getParamVal("randomGradient");

		// PARTICLE MOVEMENT
		emitterObj.startSpeed			=	makeParam(this, "instStartSpeed");
		emitterObj.startWorldSpeed 		= 	makeParam(this, "instStartWorldSpeed");

		#if !editor  // Keep startTime at 0 in Editor, since global.time is synchronized to timeline
		// var scene = local2d.getScene();
		// if(scene != null)
		// 	emitterObj.startTime = @:privateAccess scene.renderer.ctx.time;
		#end

		if (propName == null || propName == "simulationSpace") {
			switch(emitterObj.simulationSpace) {
				case World: emitterObj.getScene().addChild(emitterObj.batch);
				case Local: emitterObj.addChild(emitterObj.batch);
			}
		}

		emitterObj.init(randIdx, this);

		#if editor
		if(propName == null || ["emitShape", "emitRadius", "emitAngle1", "emitAngle2", "emitWidth", "emitHeight"].indexOf(propName) >= 0)
			updateEmitShape(emitterObj);
		#end
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		function refresh() {
			ctx.rebuildProperties();
		}

		function onChange(?pname: String) {
			if (pname == "useRandomGradient") {
				if ((props:Dynamic).useRandomGradient == true) {
					(props:Dynamic).randomGradient = Gradient.getDefaultGradientData();
				} else {
					Reflect.deleteField(props, "randomGradient");
				}
				refresh();
			}

			ctx.onChange(this, pname);

			if (pname == "warmUpTime") {
				var props : Dynamic = cast props;
				if (props.warmUpTime < 0) {
					props.warmUpTime = 0;
					hide.Ide.inst.quickError("Warm up time can no longer be negative. Use the Delay property instead");
					refresh();
				}
			}

			if(["emitShape",
				"useCollision",
				"emitType",
				"useRandomColor",
				].indexOf(pname) >= 0) {
					refresh();
				}
		}

		var params = emitterParams.copy();
		inline function removeParam(pname: String) {
			params.remove(params.find(p -> p.name == pname));
		}

		var emitShape : Emit2DShape = getParamVal("emitShape");
		if(!emitShape.match(Circle)) {
			removeParam("emitRadius");
			removeParam("emitAngle1");
			removeParam("emitAngle2");
		}
		if(!emitShape.match(Rectangle)) {
			removeParam("emitWidth");
			removeParam("emitHeight");
		}

		var isSub = findParent(Emitter) != null;
		if (!isSub) {
			removeParam("subEmitterKind");
		}

		if(!getParamVal("useRandomColor")) {
			removeParam("useRandomGradient");
			removeParam("randomColor1");
			removeParam("randomColor2");
			removeParam("randomGradient");
		}
		else {
			if (getParamVal("useRandomGradient")){
				removeParam("randomColor1");
				removeParam("randomColor2");
			} else {
				removeParam("randomGradient");
			}
		}

		var emitType : EmitType = getParamVal("emitType");
		switch (emitType) {
			case Infinity:
				removeParam("burstCount");
				removeParam("burstDelay");
				removeParam("burstParticleCount");
				removeParam("emitDuration");
				removeParam("emitRateMin");
				removeParam("emitRateMax");
				removeParam("emitRateChangeDelay");
			case InfinityRandom:
				removeParam("emitRate");
				removeParam("burstCount");
				removeParam("burstDelay");
				removeParam("burstParticleCount");
				removeParam("emitDuration");
			case BurstDuration:
				removeParam("emitRate");
				removeParam("burstCount");
				removeParam("emitRateMin");
				removeParam("emitRateMax");
				removeParam("emitRateChangeDelay");
			case Burst:
				removeParam("emitDuration");
				removeParam("emitRate");
				removeParam("emitRateMin");
				removeParam("emitRateMax");
				removeParam("emitRateChangeDelay");
			case Duration:
				removeParam("burstCount");
				removeParam("burstDelay");
				removeParam("burstParticleCount");
				removeParam("emitRateMin");
				removeParam("emitRateMax");
				removeParam("emitRateChangeDelay");
		}

		// Emitter
		{
			// Sort by groupName
			var groupNames : Array<String> = [];
			for( p in params ) {
				if( p.groupName == null && groupNames.indexOf("Emitter") == -1 )
					groupNames.push("Emitter");
				else if( p.groupName != null && groupNames.indexOf(p.groupName) == -1 )
					groupNames.push(p.groupName);
			}

			for( gn in groupNames ) {
				var params = params.filter( p -> p.groupName == (gn == "Emitter" ? null : gn) );
				var group = new hide.Element('<div class="group" name="$gn"></div>');
				group.append(hide.comp.PropsEditor.makePropsList(params));
				ctx.properties.add(group, this.props, onChange);
			}
		}

		// Instances
		{
			var groups = new Map<String, Array<ParamDef>>();
			for(p in instanceParams) {
				var groupName = p.groupName != null ? p.groupName : "Particles";

				if (!groups.exists(groupName))
					groups.set(groupName, []);
				groups[groupName].push(p);
			}

			for (groupName => params in groups)
			{
				var instGroup = new hide.Element('<div class="group" name="$groupName"></div>');
				var dl = new hide.Element('<dl>').appendTo(instGroup);

				for (p in params) {
					var dt = new hide.Element('<dt>${p.disp != null ? p.disp : p.name}</dt>').appendTo(dl);
					var dd = new hide.Element('<dd>').appendTo(dl);

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
							hide.comp.ContextMenu.createFromEvent(cast e, [
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
						var btn = new hide.Element('<input type="button" value="+"></input>').appendTo(dd);
						btn.click(function(e) {
							addUndo(p.name);
							resetParam(p);
							refresh();
						});
					}
					var dt = new hide.Element('<dt>~</dt>').appendTo(dl);
					var dd = new hide.Element('<dd>').appendTo(dl);
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
							hide.comp.ContextMenu.createFromEvent(cast e, [
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
						var btn = new hide.Element('<input type="button" value="+"></input>').appendTo(dd);
						btn.click(function(e) {
							addUndo(randProp(p.name));
							Reflect.setField(this.props, randProp(p.name), randDef);
							refresh();
						});
					}
				}

				ctx.properties.add(instGroup, this.props, onChange);
			}
		}
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "asterisk",
			name : "emitter2D",
			allowParent : function(p) return p.to(FX2D) != null || p.findParent(FX2D) != null,
			onChildUpdate: function(p) shared.editor.queueRebuild(this),
		};
	}

	function updateEmitShape(e : Emitter2DObject) {
		if (graphics != null) {
			graphics.clear();
			graphics.remove();
		}

		graphics = new h2d.Graphics(e);
		graphics.lineStyle(1, 0xFFFFFF, 1);
		switch(e.emitShape) {
			case Circle:
				var radA1 = e.evaluator.getFloat(0, e.emitAngle1, 0) * hxd.Math.PI / 180;
				var radA2 = e.evaluator.getFloat(0, e.emitAngle2, 0) * hxd.Math.PI / 180;
				graphics.drawPie(0, 0, e.evaluator.getFloat(0, e.emitRadius, 0), radA1, radA2 - radA1);
			case Rectangle:
				var width = e.evaluator.getFloat(0, e.emitWidth, 0);
				var height = e.evaluator.getFloat(0, e.emitHeight, 0);
				graphics.drawRect(-width / 2, -height / 2, width, height);
		}
	}
	#end

	inline function resetParam(param: ParamDef) {
		if(param.def is Array)
			Reflect.setField(props, param.name, cast(param.def, Array<Dynamic>).copy());
		else
			Reflect.setField(props, param.name, param.def);
	}

	static function randProp(name: String) {
		return name + "_rand";
	}

	function getParamVal(name: String, rand: Bool=false) : Dynamic {
		var param = PARAMS.get(name);
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

	static var _ = Prefab.register("emitter2D", Emitter2D);
}
