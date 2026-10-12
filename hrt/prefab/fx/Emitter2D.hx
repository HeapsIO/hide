package hrt.prefab.fx;

import hrt.prefab.fx.Emitter;
import hrt.prefab.fx.EmitterParam;
import hrt.impl.Gradient;
import hrt.prefab.Curve;

using Lambda;

typedef Vector = h2d.col.Point;

enum Emit2DShape {
	Circle;
	Rectangle;
}

enum SpriteType {
	Color;
	Texture;
	SpriteSheet;
}

@:access(hrt.prefab.fx.Emitter2DObject)
class Particle2DInstance extends h2d.SpriteBatch.BatchElement {
	public var emitter : Emitter2DObject;

	public var idx : Int;
	public var lifeTime : Float;
	public var curLifeTime : Float;

	var basisAbsPos = new h2d.col.Matrix();
	var movementAbsPos = new h2d.col.Matrix();
	var speed : Vector = new Vector();

	public function new(t : h2d.Tile, e : Emitter2DObject) {
		super(t);
		this.emitter = e;
	}

	static var tmpSpeed = new Vector();
	static var tmpVec = new Vector();
	static var tmpMat = new h2d.col.Matrix();

	override function remove() {
		super.remove();
		emitter.particles.remove(this);
	}

	override function update(dt : Float) {
		super.update(dt);

		getInitialAbsPos(basisAbsPos, dt);
		getCurrentAbsPos(movementAbsPos, dt);

		var absPos = new h2d.col.Matrix();
		absPos.multiply(basisAbsPos, movementAbsPos);

		this.x = absPos.getPosition().x;
		this.y = absPos.getPosition().y;

		var d = new Vector(1, 0);
		d.transform2x2(absPos);
		this.rotation = d.getRotation();

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
						m.initRotate(new Vector(posX, posY).getRotation());

					m.translate(posX, posY);

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
						m.initRotate(new Vector(posX, posY).getRotation());

					m.translate(posX, posY);
			}

			// START LOCAL SPEED
			evaluator.getVector2(idx, emitter.startSpeed, emitter.curTime, tmpVec);
			tmpVec.transform2x2(m);
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
			tmpVec.transform2x2(m);
			speed += tmpVec;
		}

		// WORLD ACCELERATION
		if (def.worldAcceleration != VZero) {
			evaluator.getVector2(idx, def.worldAcceleration, t, tmpVec);
			tmpVec.scale(dt);
			tmpVec.transform2x2(emitter.invTransform);
			speed += tmpVec;
		}

		tmpSpeed.set(speed.x, speed.y);

		// SPEED
		if (def.localSpeed != VZero) {
			evaluator.getVector2(idx, def.localSpeed, t, tmpVec);
			tmpVec.transform2x2(m);
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

		m.translate(tmpSpeed.x * dt, tmpSpeed.y * dt);

		if (def.orbitSpeed != VZero) {
			var orbitSpeed = evaluator.getFloat(idx, def.orbitSpeed, t);

			var factorOverTime = evaluator.getFloat(idx, def.orbitSpeedOverTime, emitter.curTime);
			orbitSpeed *= factorOverTime;

			var prevPos = m.getPosition().clone();
			tmpMat.initRotate(orbitSpeed * dt);
			tmpMat.multiply(m, tmpMat);
			var delta = tmpMat.getPosition().sub(prevPos);
			m.prependTranslate(delta.x, delta.y);

			// Take transform into account into local speed
			delta.scale(1 / dt);
			tmpSpeed.x += delta.x;
			tmpSpeed.y += delta.y;
		}

		if (emitter.emitOrientation.match(Speed) && hxd.Math.abs(tmpSpeed.length()) > 0.0001) {
			var targetRotation = tmpSpeed.getRotation();
			basisAbsPos.rotate(targetRotation);
		}
	}
}

/** The values an `Emitter2DObject` is built with, see `Emitter2D.makeValues`. **/
@:publicFields
class Emitter2DValues {
	var instDef : InstanceDef;
	var startSpeed : Value;
	var startWorldSpeed : Value;
	var emitRate : Value;
	var emitRateMin : Value;
	var emitRateMax : Value;
	var burstParticleCount : Value;
	var emitRadius : Value;
	var emitAngle1 : Value;
	var emitAngle2 : Value;
	var emitWidth : Value;
	var emitHeight : Value;
	var lifeTime : Float;
	var lifeTimeRand : Float;
	/** Holds the random slots allocated by the values **/
	var builder : ParamBuilder;
	function new() { }
}

class Emitter2DObject extends h2d.Object {
	public var particles : Array<Particle2DInstance> = [];
	public var batch : h2d.SpriteBatch;
	var evaluator : Evaluator;
	var rand : hxd.Rand;

	var prevTime : Float;
	var curTime = 0.;
	var countToEmit = 0.;
	var totalBurstCount = 0;
	var randomValues : Array<Float>;
	var randSlots : Int;
	var instanceCounter = 0;
	var animatedTexShader : h3d.shader.AnimatedTexture = null;

	// Emitter parameters
	public var instDef : InstanceDef;
	public var seed = 0;
	public var lifeTime = 2.0;
	public var lifeTimeRand = 0.0;
	public var speedFactor = 1.0;
	public var warmUpTime = 0.0;
	public var delay = 0.0;
	public var emitOrientation : Orientation = Forward;
	public var emitType : EmitType = Infinity;
	public var burstCount : Int = 1;
	public var burstParticleCount : Value;
	public var burstDelay : Float = 1.0;
	public var emitDuration : Float = 1.0;
	public var emitRate : Value;
	public var emitRateMin : Value;
	public var emitRateMax : Value;
	public var emitRateChangeDelay : Float = 1.0;
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
	public var spriteType : SpriteType = Color;
	public var color : h3d.Vector;
	public var texture : String;
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

	public function new(?parent) {
		super(parent);

		batch = new h2d.SpriteBatch(h2d.Tile.fromColor(0xFF00FF, 10, 10), this);
		batch.hasRotationScale = true;
		evaluator = new Evaluator([0], 1);
		rand = new hxd.Rand(seed);
	}

	public function init(randSlots: Int, prefab: Emitter2D) {
		var randomValues = [for(_ in 0...(maxCount * randSlots)) rand.srand()];
		evaluator = new Evaluator(randomValues, randSlots);

		if (animatedTexShader != null)
			batch.removeShader(animatedTexShader);

		if (spriteSheet != null) {
			var tex = hxd.res.Loader.currentInstance.load(spriteSheet).toTexture();
			animatedTexShader = new h3d.shader.AnimatedTexture(tex, frameDivisionX, frameDivisionY, frameCount, frameCount * animationSpeed / lifeTime);
			animatedTexShader.useSourceUVs = animationUseSourceUVs;
			animatedTexShader.startTime = 0;
			animatedTexShader.loop = animationLoop;
			animatedTexShader.blendBetweenFrames = animationBlendBetweenFrames;
			animatedTexShader.setPriority(1);
			batch.addShader(animatedTexShader);
		}
	}

	public function setTime(time : Float, inCatchup : Bool = false) {
		prevTime = curTime;
		curTime = (time * speedFactor + warmUpTime) - delay;

		if (curTime < 0) {
			if (prevTime > 0)
				reset();
			return;
		}

		var dt = curTime - prevTime;
		if ((dt < 0 || dt > hxd.Timer.maxDeltaTime) && !inCatchup) {
			reset();
			var targetTime = curTime;
			prevTime = 0;
			curTime = 0;
			var t = 0.;
			while (curTime < targetTime) {
				t = hxd.Math.min(t + hxd.Timer.dt, targetTime);
				setTime(t - warmUpTime + delay, true);
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
		var t = h2d.Tile.fromColor(0xFF00FF, 10, 10);
		switch (spriteType) {
			case Color:
				if (!useRandomColor && !useRandomGradient)
					t = h2d.Tile.fromColor(color.toColor(), 10, 10);
				else if (useRandomColor && !useRandomGradient) {
					var c = new h3d.Vector();
					c.lerp(randomColor1, randomColor2, rand.rand());
					t = h2d.Tile.fromColor(c.toColor(), 10, 10);
				}
				else if (useRandomGradient) {
					t = h2d.Tile.fromColor(Gradient.evalData(randomGradient, rand.rand()).toColor(), 10, 10);
				}
			case Texture:
				t = h2d.Tile.fromTexture(hxd.res.Loader.currentInstance.load(texture).toTexture());
			default:
		}

		t.dx = -t.width / 2;
		t.dy = -t.height / 2;
		return t;
	}
}

@:access(hrt.prefab.fx.Emitter2DObject)
@:prefabName("Emitter 2D")
@:prefabIcon(hrt.ui.HuiRes.ui.icons.prefab.emitter2d)
class Emitter2D extends Object2D {

	public static var emitterParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = [
		// PROPERTIES
		{ name: "speedFactor", disp: "Speed Factor", t: PFloat(0, 1), def: 1.0, groupName : "Properties" },
		{ name: "seed", t: PInt(0, 100), def: 0, groupName : "Properties", disp: "Seed"},

		// EMISSION
		{ name: "warmUpTime", disp: "Warm Up", t: PFloat(0, 1), def: 0.0, groupName : "Emission" },
		{ name: "delay", disp: "Delay", t: PFloat(0, 10), def: 0.0, groupName : "Emission" },
		{ name: "emitType", t: PEnum(EmitType), def: EmitType.Infinity, disp: "Type", groupName : "Emission"  },
		{ name: "emitDuration", t: PFloat(0, 10.0), disp: "Duration", def : 1.0, groupName : "Emission" },
		{ name: "emitRate", t: PInt(0, 100), def: 5, disp: "Rate", animate: true, groupName : "Emission" },
		{ name: "emitRateMin", t: PInt(0, 100), def: 5, disp: "Rate Min", animate: true, groupName : "Emission" },
		{ name: "emitRateMax", t: PInt(0, 100), def: 5, disp: "Rate Max", animate: true, groupName : "Emission" },
		{ name: "emitRateChangeDelay", t: PFloat(0.01, 5.0), def: 1.0, disp: "Rate Change Time", groupName : "Emission" },
		{ name: "burstCount", t: PInt(1, 10), disp: "Count", def : 1, groupName : "Emission" },
		{ name: "burstDelay", t: PFloat(0, 1.0), disp: "Delay", def : 1.0, groupName : "Emission" },
		{ name: "burstParticleCount", t: PInt(1, 10), disp: "Particle Count", def : 1, groupName : "Emission", animate: true },
		{ name: "maxCount", t: PInt(0, 100), def: 20, groupName : "Emission" },
		{ name: "emitOrientation", t: PEnum(Orientation), def: Orientation.Forward, disp: "Orientation", groupName : "Emission" },

		// SHAPE EMISSION
		{ name: "emitShape", t: PEnum(Emit2DShape), def: Emit2DShape.Circle, disp: "Shape", groupName : "Shape Emission" },
		{ name: "emitRadius", t: PFloat(0, 360.0), def: 20.0, disp: "Radius", groupName : "Shape Emission", animate: true },
		{ name: "emitAngle1", t: PFloat(0, 360.0), def: 20.0, disp: "Angle 1", groupName : "Shape Emission", animate: true },
		{ name: "emitAngle2", t: PFloat(0, 360.0), def: 40.0, disp: "Angle 2", groupName : "Shape Emission", animate: true },
		{ name: "emitWidth", t: PFloat(0, 10.0), def: 1.0, disp: "Width", groupName : "Shape Emission", animate: true },
		{ name: "emitHeight", t: PFloat(0, 10.0), def: 1.0, disp: "Height", groupName : "Shape Emission", animate: true },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface", groupName : "Shape Emission" },

		// PARTICLE
		{ name: "spriteType", t: PEnum(SpriteType), def: SpriteType.Color, groupName : "Particle" },
		{ name: "color", t: PVec(4), def: [0,0,0,1], groupName : "Particle" },
		{ name: "texture", t: PTexture, def: "", groupName : "Particle" },
		{ name: "useRandomColor", t: PBool, def: false, disp: "Random Color", groupName : "Particle" },
		{ name: "useRandomGradient", t: PBool, def: false, disp: "Random Gradient", groupName : "Particle" },
		{ name: "randomColor1", t: PVec(4), disp: "Color 1", def : [0,0,0,1], groupName : "Particle" },
		{ name: "randomColor2", t: PVec(4), disp: "Color 2", def : [1,1,1,1], groupName : "Particle" },
		{ name: "randomGradient", t:PGradient, disp: "Gradient", def: null, groupName : "Particle" },
		{ name: "spriteSheet", t: PFile(["jpg","png"]), def: null, groupName : "Particle", disp: "Sheet" },
		{ name: "frameCount", t: PInt(0), def: 0, groupName : "Particle", disp: "Frames" },
		{ name: "frameDivisionX", t: PInt(1), def: 1, groupName : "Particle", disp: "Divisions X" },
		{ name: "frameDivisionY", t: PInt(1), def: 1, groupName : "Particle", disp: "Divisions Y" },
		{ name: "animationSpeed", t: PFloat(0, 2.0), def: 1.0, groupName : "Particle", disp: "Speed" },
		{ name: "animationLoop", t: PBool, def: true, groupName : "Particle", disp: "Loop" },
		{ name: "animationUseSourceUVs", t: PBool, def: true, groupName : "Particle", disp: "Use Source UV" },
		{ name: "animationBlendBetweenFrames", t: PBool, def: true, groupName : "Particle", disp: "Blend frames" },
	];

	/** Version of the param format, the older one is upgraded on load (see `EmitterUpgrade`) **/
	public static inline var PARAMS_VERSION = 2;

	/** The params with modes, see `EmitterParam`. The other ones are `emitterParams`. **/
	public static var MODE_PARAMS : Array<ModeParamDef> = [
		{ name: "lifeTime", disp: "Life Time", group: Spawn, def: [1.], min: 0, max: 10, category: "Particle" },
		// PARTICLE TRANSFORM
		{ name: "scale", disp: "Scale", group: Particle, def: [1.], min: 0, max: 2, category: "Particle Transform" },
		{ name: "scaleMultiplier", disp: "Scale Multiplier", group: Multiplier, def: [1.], min: 0, max: 2, category: "Particle Transform", track: "instScaleOverTime" },
		{ name: "stretch", disp: "Stretch", group: Particle, def: [1., 1.], min: 0, max: 2, category: "Particle Transform" },
		{ name: "rotation", disp: "Rotation", group: Particle, def: [0.], min: 0, max: 360, category: "Particle Transform" },
		{ name: "offset", disp: "Offset", group: Particle, def: [0., 0.], min: -10, max: 10, category: "Particle Transform" },
		// PARTICLE MOVEMENT
		{ name: "acceleration", disp: "Acceleration", group: Particle, def: [0., 0.], min: -10, max: 10, category: "Particle Movement" },
		{ name: "worldAcceleration", disp: "World Acceleration", group: Particle, def: [0., 0.], min: -10, max: 10, category: "Particle Movement" },
		{ name: "speed", disp: "Fixed Speed", group: Particle, def: [0., 0.], min: -10, max: 10, category: "Particle Movement" },
		{ name: "worldSpeed", disp: "Fixed World Speed", group: Particle, def: [0., 0.], min: -10, max: 10, category: "Particle Movement" },
		{ name: "startSpeed", disp: "Start Speed", group: Spawn, def: [0., 0.], min: -10, max: 10, category: "Particle Movement", track: "instStartSpeed" },
		{ name: "startWorldSpeed", disp: "Start World Speed", group: Spawn, def: [0., 0.], min: -10, max: 10, category: "Particle Movement", track: "instStartWorldSpeed" },
		{ name: "orbitSpeed", disp: "Orbit Speed", group: Particle, def: [0.], min: -10, max: 10, category: "Particle Movement" },
		{ name: "orbitSpeedMultiplier", disp: "Orbit Speed Multiplier", group: Multiplier, def: [1.], min: 0, max: 2, category: "Particle Movement", track: "instOrbitSpeedOverTime" },
		// PARTICLE LIMIT VELOCITY
		{ name: "maxVelocity", disp: "Max Velocity", group: Particle, def: [0.], min: 0, max: 10, category: "Particle Limit Velocity" },
		{ name: "dampen", disp: "Dampen", group: Particle, def: [0.], min: 0, max: 10, category: "Particle Limit Velocity" },
	];
	public static var MODE_PARAMS_BY_NAME = [for( p in MODE_PARAMS ) p.name => p];

	/** The animation curves of the spawn and multiplier params, as tracks of the FX timeline **/
	public static var instanceParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = [for( p in MODE_PARAMS ) if( p.track != null ) ({
		name: p.track,
		disp: p.disp,
		t: p.def.length > 1 ? PVec(p.def.length, p.min, p.max) : PFloat(p.min, p.max),
		def: p.def.length > 1 ? (p.def : Dynamic) : (p.def[0] : Dynamic),
		groupName: p.category,
		animate: true,
		instance: false,
	} : hrt.prefab.fx.EmitterHelper.ParamDef)];

	/** The old params added to their curve instead of being multiplied by it **/
	static var LEGACY_ADDITIVE = ["Rotation", "Offset"];

	/** The params with modes by name (see `MODE_PARAMS`), missing when all their components are unset **/
	public var params : Map<String, ParamValue> = [];

	/** See `Emitter.skippedRandomSlots` **/
	public var skippedRandomSlots : Array<String> = null;

	public static var PARAMS : Map<String, hrt.prefab.fx.EmitterHelper.ParamDef> = {
		var map = new Map();
		for(e in emitterParams) {
			map.set(e.name, e);
		}
		for(i in instanceParams)
			map.set(i.name, i);
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
				EmitterHelper.resetParam(props, param);
		}
	}

	override function save() {
		var data = super.save();
		data.props = Reflect.copy(props);
		for(param in PARAMS) {
			var f : Dynamic = Reflect.field(props, param.name);
			if(f != null && haxe.Json.stringify(f) != haxe.Json.stringify(param.def)) {
				var val : Dynamic = f;
				switch(param.t) {
					case PEnum(en):
						val = Type.enumConstructor(val);
					default:
				}
				Reflect.setField(data.props, param.name, val);
			}
			else {
				Reflect.deleteField(data.props, param.name);
			}
		}
		var props : Dynamic = data.props;
		props.paramsVersion = PARAMS_VERSION;
		for( p in MODE_PARAMS ) {
			var v = EmitterParam.save(params.get(p.name));
			if( v != null )
				Reflect.setField(props, p.name, v);
		}
		if( skippedRandomSlots != null )
			props.skippedRandomSlots = skippedRandomSlots.copy();
		return data;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		// props is the loaded data itself, which is not ours to change
		props = Reflect.copy(props) ?? {};
		for(param in emitterParams) {
			if(Reflect.hasField(obj.props, param.name)) {
				var val : Dynamic = Reflect.field(obj.props, param.name);
				switch(param.t) {
					case PEnum(en):
						#if editor
						try {
						#end
							val = Type.createEnum(en, val);
						#if editor
						} catch (e) {
							val = param.def;
						};
						#end
					default:
				}
				Reflect.setField(props, param.name, val);
			}
			else if(param.def != null)
				EmitterHelper.resetParam(props, param);
			else if (param.name == "randomGradient")
				(props:Dynamic).randomGradient = Gradient.getDefaultGradientData();
		}

		var data : Dynamic = obj.props ?? {};
		params = [];
		for( p in MODE_PARAMS ) {
			var v = EmitterParam.parse(Reflect.field(data, p.name), p.def.length);
			if( v != null )
				params.set(p.name, v);
		}
		var skips : Array<Dynamic> = data.skippedRandomSlots;
		skippedRandomSlots = skips == null ? null : [for( s in skips ) Std.string(s)];
		var legacy = data.paramsVersion == null;
		if( legacy || EmitterUpgrade.hasLegacyFields(data, MODE_PARAMS) ) {
			var skips = EmitterUpgrade.upgradeEmitter(this, data, obj.children, MODE_PARAMS, LEGACY_ADDITIVE, legacy, params);
			if( skips != null )
				skippedRandomSlots = (skippedRandomSlots ?? []).concat(skips);
		}
		// the params with modes are not kept in props, nor their old fields
		var props : Dynamic = props;
		for( p in MODE_PARAMS ) {
			var old = EmitterUpgrade.LEGACY_NAMES.get(p.name);
			for( f in [p.name, old, old + "_rand", p.name + "Rand"] )
				Reflect.deleteField(props, f);
		}
		Reflect.deleteField(props, "paramsVersion");
		Reflect.deleteField(props, "skippedRandomSlots");
	}

	override function copy(obj:Prefab) {
		super.copy(obj);
		for(param in emitterParams) {
			if(Reflect.hasField(obj.props, param.name)) {
				var val : Dynamic = Reflect.field(obj.props, param.name);
				/*switch(param.t) {
					case PEnum(en):
						val = Type.createEnum(en, val);
					default:
				}*/
				Reflect.setField(props, param.name, val);
			}
			else if(param.def != null)
				EmitterHelper.resetParam(props, param);
		}
		var from : Emitter2D = cast obj;
		params = [for( k => v in from.params ) k => v.copy()];
		skippedRandomSlots = from.skippedRandomSlots?.copy();
	}

	public function getParam( name : String ) : Null<ParamValue> {
		return params.get(name);
	}

	/** Sets the modes of a param, null to unset all its components. **/
	public function setParam( name : String, v : Null<ParamValue> ) {
		if( EmitterParam.isUnset(v) )
			params.remove(name);
		else
			params.set(name, v);
	}

	/**
		The values the emitter object is built with. They are built in the order of the old
		code, which allocated the random slots in that order.
	**/
	public function makeValues() : Emitter2DValues {
		var b = new ParamBuilder(this, skippedRandomSlots);
		inline function param( name : String ) return b.param(MODE_PARAMS_BY_NAME.get(name), params.get(name));
		inline function animated( name : String ) {
			var v : Float = EmitterHelper.getParamVal(PARAMS, props, name);
			return b.animated(Evaluator.vVal(v), name, name);
		}
		var d = new InstanceDef();
		d.localSpeed = param("speed");
		d.worldSpeed = param("worldSpeed");
		d.orbitSpeed = param("orbitSpeed");
		d.orbitSpeedOverTime = param("orbitSpeedMultiplier");
		d.acceleration = param("acceleration");
		d.worldAcceleration = param("worldAcceleration");
		d.localOffset = param("offset");
		d.scale = param("scale");
		d.scaleOverTime = param("scaleMultiplier");
		d.dampen = param("dampen");
		d.maxVelocity = param("maxVelocity");
		d.stretch = param("stretch");
		d.rotation = param("rotation");
		var v = new Emitter2DValues();
		v.instDef = d;
		v.burstParticleCount = animated("burstParticleCount");
		v.emitRate = animated("emitRate");
		v.emitRateMin = animated("emitRateMin");
		v.emitRateMax = animated("emitRateMax");
		v.emitRadius = animated("emitRadius");
		v.emitAngle1 = animated("emitAngle1");
		v.emitAngle2 = animated("emitAngle2");
		v.emitWidth = animated("emitWidth");
		v.emitHeight = animated("emitHeight");
		v.startSpeed = param("startSpeed");
		v.startWorldSpeed = param("startWorldSpeed");
		// drawn on the emitter random stream when the particle spawns
		var life = params.get("lifeTime");
		var span = EmitterParam.span(life == null ? null : life[0], 1.0);
		v.lifeTime = (span.min + span.max) * 0.5;
		v.lifeTimeRand = (span.max - span.min) * 0.5;
		v.builder = b;
		return v;
	}

	override function makeObject(parent2d : h2d.Object) {
		return new Emitter2DObject(parent2d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var emitterObj = Std.downcast(local2d, Emitter2DObject);
		var values = makeValues();
		emitterObj.instDef = values.instDef;
		emitterObj.blendMode  			= 	this.blendMode;
		emitterObj.batch.blendMode      =   this.blendMode;
		emitterObj.spriteType          	= 	EmitterHelper.getParamVal(PARAMS, props, "spriteType");
		emitterObj.texture 			   	= 	EmitterHelper.getParamVal(PARAMS, props, "texture");
		emitterObj.color 			   	= 	EmitterHelper.getParamVal(PARAMS, props, "color");
		emitterObj.seed 			    = 	EmitterHelper.getParamVal(PARAMS, props, "seed");
		emitterObj.lifeTime 			= 	values.lifeTime;
		emitterObj.lifeTimeRand 		= 	values.lifeTimeRand;
		emitterObj.speedFactor 			= 	EmitterHelper.getParamVal(PARAMS, props, "speedFactor");
		emitterObj.warmUpTime 			= 	EmitterHelper.getParamVal(PARAMS, props, "warmUpTime");
		emitterObj.delay 				= 	EmitterHelper.getParamVal(PARAMS, props, "delay");
		emitterObj.emitType 			= 	EmitterHelper.getParamVal(PARAMS, props, "emitType");
		emitterObj.burstCount 			= 	EmitterHelper.getParamVal(PARAMS, props, "burstCount");
		emitterObj.burstDelay 			= 	EmitterHelper.getParamVal(PARAMS, props, "burstDelay");
		emitterObj.burstParticleCount 	= 	values.burstParticleCount;
		emitterObj.emitDuration 		= 	EmitterHelper.getParamVal(PARAMS, props, "emitDuration");
		emitterObj.emitOrientation 		= 	EmitterHelper.getParamVal(PARAMS, props, "emitOrientation");
		emitterObj.maxCount 			= 	EmitterHelper.getParamVal(PARAMS, props, "maxCount");
		emitterObj.emitRate 			= 	values.emitRate;
		emitterObj.emitRateMin 			= 	values.emitRateMin;
		emitterObj.emitRateMax 			= 	values.emitRateMax;
		emitterObj.emitRateChangeDelay 	= 	EmitterHelper.getParamVal(PARAMS, props, "emitRateChangeDelay");
		emitterObj.emitShape 			= 	EmitterHelper.getParamVal(PARAMS, props, "emitShape");
		emitterObj.emitRadius 			= 	values.emitRadius;
		emitterObj.emitAngle1 			= 	values.emitAngle1;
		emitterObj.emitAngle2 			= 	values.emitAngle2;
		emitterObj.emitWidth 			= 	values.emitWidth;
		emitterObj.emitHeight 			= 	values.emitHeight;
		emitterObj.emitSurface 			= 	EmitterHelper.getParamVal(PARAMS, props, "emitSurface");
		emitterObj.spriteSheet 			= 	EmitterHelper.getParamVal(PARAMS, props, "spriteSheet");
		emitterObj.frameCount 			= 	EmitterHelper.getParamVal(PARAMS, props, "frameCount");
		emitterObj.frameDivisionX 		= 	EmitterHelper.getParamVal(PARAMS, props, "frameDivisionX");
		emitterObj.frameDivisionY 		= 	EmitterHelper.getParamVal(PARAMS, props, "frameDivisionY");
		emitterObj.animationSpeed 		= 	EmitterHelper.getParamVal(PARAMS, props, "animationSpeed");
		emitterObj.animationLoop 		= 	EmitterHelper.getParamVal(PARAMS, props, "animationLoop");
		emitterObj.animationUseSourceUVs 			= 	EmitterHelper.getParamVal(PARAMS, props, "animationUseSourceUVs");
		emitterObj.animationBlendBetweenFrames 		= 	EmitterHelper.getParamVal(PARAMS, props, "animationBlendBetweenFrames");
		emitterObj.useRandomColor 		= 	EmitterHelper.getParamVal(PARAMS, props, "useRandomColor");
		emitterObj.useRandomGradient 	= 	EmitterHelper.getParamVal(PARAMS, props, "useRandomGradient");
		emitterObj.randomColor1 		= 	EmitterHelper.getParamVal(PARAMS, props, "randomColor1");
		emitterObj.randomColor2 		= 	EmitterHelper.getParamVal(PARAMS, props, "randomColor2");
		emitterObj.randomGradient 		= 	EmitterHelper.getParamVal(PARAMS, props, "randomGradient");
		emitterObj.startSpeed			=	values.startSpeed;
		emitterObj.startWorldSpeed 		= 	values.startWorldSpeed;

		emitterObj.init(values.builder.slots.length, this);

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

			if (pname == "spriteType") {
				if ((props:Dynamic).spriteType != SpriteType.SpriteSheet)
					(props:Dynamic).spriteSheet = null;
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
				"useRandomColor"
				].indexOf(pname) >= 0) {
					refresh();
				}
		}

		var params = emitterParams.copy();
		inline function removeParam(pname: String) {
			params.remove(params.find(p -> p.name == pname));
		}

		var emitShape : Emit2DShape = EmitterHelper.getParamVal(PARAMS, props, "emitShape");
		if(!emitShape.match(Circle)) {
			removeParam("emitRadius");
			removeParam("emitAngle1");
			removeParam("emitAngle2");
		}
		if(!emitShape.match(Rectangle)) {
			removeParam("emitWidth");
			removeParam("emitHeight");
		}

		var spriteType = EmitterHelper.getParamVal(PARAMS, props, "spriteType");
		if (spriteType != SpriteType.Color) {
			removeParam("color");
			removeParam("useRandomColor");
		}
		if (spriteType != SpriteType.Texture) {
			removeParam("texture");
		}
		if (spriteType != SpriteType.SpriteSheet) {
			removeParam("spriteSheet");
			removeParam("frameCount");
			removeParam("frameDivisionX");
			removeParam("frameDivisionY");
			removeParam("animationSpeed");
			removeParam("animationLoop");
			removeParam("animationUseSourceUVs");
			removeParam("animationBlendBetweenFrames");
		}

		if(!EmitterHelper.getParamVal(PARAMS, props, "useRandomColor")) {
			removeParam("useRandomGradient");
			removeParam("randomColor1");
			removeParam("randomColor2");
			removeParam("randomGradient");
		}
		else {
			if (EmitterHelper.getParamVal(PARAMS, props, "useRandomGradient")){
				removeParam("randomColor1");
				removeParam("randomColor2");
			} else {
				removeParam("randomGradient");
			}
		}

		var emitType : EmitType = EmitterHelper.getParamVal(PARAMS, props, "emitType");
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

		EmitterHelper.generateEdit(params, [], props, ctx.properties, onChange, refresh);
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "asterisk",
			name : "Emitter 2D",
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

	static var _ = Prefab.register("emitter2D", Emitter2D);
}
