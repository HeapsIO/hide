package hrt.prefab.fx;

import hrt.prefab.fx.Emitter;
import hrt.prefab.fx.EmitterParam;
import hrt.impl.Gradient;

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
		if (def.offset != VZero) {
			evaluator.getVector2(idx, def.offset, t, tmpVec);
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
		tmpVec *= evaluator.getFloat(idx, def.scaleMultiplier, emitter.curTime);
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
		if (def.speed != VZero) {
			evaluator.getVector2(idx, def.speed, t, tmpVec);
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

			// degrees per second
			var factorOverTime = evaluator.getFloat(idx, def.orbitSpeedMultiplier, emitter.curTime);
			orbitSpeed *= factorOverTime * (Math.PI / 180.0);

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

class Emitter2DObject extends h2d.Object {
	public var particles : Array<Particle2DInstance> = [];
	public var batch : h2d.SpriteBatch;
	var evaluator : Evaluator;
	var rand : hxd.Rand;

	var prevTime : Float;
	var curTime = 0.;
	var countToEmit = 0.;
	var totalBurstCount = 0;
	var instanceCounter = 0;
	var animatedTexShader : h3d.shader.AnimatedTexture = null;

	// Emitter parameters
	public var instDef : InstanceDef;
	public var seed = 0;
	public var lifeTime : Value = VConst(2.0);
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
		evaluator = new Evaluator();
		rand = new hxd.Rand(seed);
	}

	public function init(randSlots: Int, prefab: Emitter2D) {
		evaluator.allocRandom(maxCount, randSlots);
		evaluator.resetRandom(rand);

		if (animatedTexShader != null)
			batch.removeShader(animatedTexShader);

		if (spriteSheet != null) {
			var tex = hxd.res.Loader.currentInstance.load(spriteSheet).toTexture();
			var meanLifeTime = evaluator.getMean(lifeTime);
			animatedTexShader = new h3d.shader.AnimatedTexture(tex, frameDivisionX, frameDivisionY, frameCount, frameCount * animationSpeed / meanLifeTime);
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
			part.idx = instanceCounter;
			part.lifeTime = evaluator.getFloat(part.idx, lifeTime, curTime);
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
		evaluator.resetRandom(rand);
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
@:build(hrt.prefab.fx.EmitterMacros.build("hrt.prefab.fx.Emitter2D.Emitter2DObject"))
class Emitter2D extends Object2D implements ParamOwner {

	@:group("Properties")
	@:s @:range(0, 1) public var speedFactor : Float = 1.0;
	@:s @:range(0, 100) public var seed : Int = 0;

	@:group("Emission")
	@:s @:range(0, 1) @:disp("Warm Up") public var warmUpTime : Float = 0.0;
	@:s @:range(0, 10) public var delay : Float = 0.0;
	@:s @:disp("Type") public var emitType : EmitType = EmitType.Infinity;
	@:s @:range(0, 10.0) @:disp("Duration") public var emitDuration : Float = 1.0;
	@:s @:range(0, 100) @:animate @:disp("Rate") public var emitRate : Float = 5;
	@:s @:range(0, 100) @:animate @:disp("Rate Min") public var emitRateMin : Float = 5;
	@:s @:range(0, 100) @:animate @:disp("Rate Max") public var emitRateMax : Float = 5;
	@:s @:range(0.01, 5.0) @:disp("Rate Change Time") public var emitRateChangeDelay : Float = 1.0;
	@:s @:range(1, 10) @:disp("Count") public var burstCount : Int = 1;
	@:s @:range(0, 1.0) @:disp("Delay") public var burstDelay : Float = 1.0;
	@:s @:range(1, 10) @:animate @:disp("Particle Count") public var burstParticleCount : Float = 1;
	@:s @:range(0, 100) public var maxCount : Int = 20;
	@:s @:disp("Orientation") public var emitOrientation : Orientation = Orientation.Forward;

	@:group("Shape Emission")
	@:s @:disp("Shape") public var emitShape : Emit2DShape = Emit2DShape.Circle;
	@:s @:range(0, 360.0) @:animate @:disp("Radius") public var emitRadius : Float = 20.0;
	@:s @:range(0, 360.0) @:animate @:disp("Angle 1") public var emitAngle1 : Float = 20.0;
	@:s @:range(0, 360.0) @:animate @:disp("Angle 2") public var emitAngle2 : Float = 40.0;
	@:s @:range(0, 10.0) @:animate @:disp("Width") public var emitWidth : Float = 1.0;
	@:s @:range(0, 10.0) @:animate @:disp("Height") public var emitHeight : Float = 1.0;
	@:s @:disp("Surface") public var emitSurface : Bool = false;

	@:group("Particle")
	@:s public var spriteType : SpriteType = SpriteType.Color;
	@:s public var color : Array<Float> = [0., 0., 0., 1.];
	@:s public var texture : String = "";
	@:s @:disp("Random Color") public var useRandomColor : Bool = false;
	@:s @:disp("Random Gradient") public var useRandomGradient : Bool = false;
	@:s @:disp("Color 1") public var randomColor1 : Array<Float> = [0., 0., 0., 1.];
	@:s @:disp("Color 2") public var randomColor2 : Array<Float> = [1., 1., 1., 1.];
	@:s @:disp("Gradient") public var randomGradient : hrt.impl.Gradient.GradientData;
	@:s @:t(PFile(["jpg", "png"])) @:disp("Sheet") public var spriteSheet : String;
	@:s @:range(0) @:disp("Frames") public var frameCount : Int = 0;
	@:s @:range(1) @:disp("Divisions X") public var frameDivisionX : Int = 1;
	@:s @:range(1) @:disp("Divisions Y") public var frameDivisionY : Int = 1;
	@:s @:range(0, 2.0) @:disp("Speed") public var animationSpeed : Float = 1.0;
	@:s @:disp("Loop") public var animationLoop : Bool = true;
	@:s @:disp("Use Source UV") public var animationUseSourceUVs : Bool = true;
	@:s @:disp("Blend Frames") public var animationBlendBetweenFrames : Bool = true;

	@:group("Particle Movement")
	@:param(PVec(2, -10, 10), Particle) @:disp("Fixed Speed") public var speed : ParamValue;
	@:param(PVec(2, -10, 10), Particle) @:disp("Fixed World Speed") public var worldSpeed : ParamValue;
	/** Degrees per second **/
	@:param(PFloat(-360, 360), Particle) public var orbitSpeed : ParamValue;
	@:param(PFloat(0, 2), Multiplier, 1.) public var orbitSpeedMultiplier : ParamValue;
	@:param(PVec(2, -10, 10), Particle) public var acceleration : ParamValue;
	@:param(PVec(2, -10, 10), Particle) public var worldAcceleration : ParamValue;
	@:param(PVec(2, -10, 10), Spawn) public var startSpeed : ParamValue;
	@:param(PVec(2, -10, 10), Spawn) public var startWorldSpeed : ParamValue;
	@:group("Particle Transform")
	@:param(PVec(2, -10, 10), Particle) public var offset : ParamValue;
	@:param(PFloat(0, 2), Particle, 1.) public var scale : ParamValue;
	@:param(PFloat(0, 2), Multiplier, 1.) public var scaleMultiplier : ParamValue;
	@:param(PVec(2, 0, 2), Particle, [1., 1.]) public var stretch : ParamValue;
	/** Degrees. Not named `rotation`, the one of the emitter object **/
	@:param(PFloat(0, 360), Particle) @:name("rotation") public var particleRotation : ParamValue;
	@:group("Particle Limit Velocity")
	@:param(PFloat(0, 10), Particle) public var dampen : ParamValue;
	@:param(PFloat(0, 10), Particle) public var maxVelocity : ParamValue;
	@:group("Particle")
	@:param(PFloat(0, 10), Spawn, 1.) public var lifeTime : ParamValue;

	#if editor
	var graphics : h2d.Graphics;
	#end

	override function save() {
		var data = super.save();
		saveParams(data);
		if( !useRandomColor || !useRandomGradient )
			Reflect.deleteField(data, "randomGradient");
		if( !FX.inFX(this) )
			data.version = FX.VERSION;
		return data;
	}

	override function load( obj : Dynamic ) {
		if( !FX.inFX(this) )
			FX.checkVersion(this, obj);
		super.load(obj);
		loadParams(obj);
		if( randomGradient == null && useRandomGradient )
			randomGradient = Gradient.getDefaultGradientData();
	}

	override function copy(obj:Prefab) {
		super.copy(obj);
		copyParams(cast obj);
	}

	override function makeObject(parent2d : h2d.Object) {
		return new Emitter2DObject(parent2d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var emitterObj = Std.downcast(local2d, Emitter2DObject);
		var params = makeValues(emitterObj);
		emitterObj.blendMode  			= 	this.blendMode;
		emitterObj.batch.blendMode      =   this.blendMode;
		emitterObj.spriteType          	= 	spriteType;
		emitterObj.texture 			   	= 	texture;
		emitterObj.color 			   	= 	h3d.Vector.fromArray(color);
		emitterObj.seed 			    = 	seed;
		emitterObj.speedFactor 			= 	speedFactor;
		emitterObj.warmUpTime 			= 	warmUpTime;
		emitterObj.delay 				= 	delay;
		emitterObj.emitType 			= 	emitType;
		emitterObj.burstCount 			= 	burstCount;
		emitterObj.burstDelay 			= 	burstDelay;
		emitterObj.emitDuration 		= 	emitDuration;
		emitterObj.emitOrientation 		= 	emitOrientation;
		emitterObj.maxCount 			= 	maxCount;
		emitterObj.emitRateChangeDelay 	= 	emitRateChangeDelay;
		emitterObj.emitShape 			= 	emitShape;
		emitterObj.emitSurface 			= 	emitSurface;
		emitterObj.spriteSheet 			= 	spriteSheet;
		emitterObj.frameCount 			= 	frameCount;
		emitterObj.frameDivisionX 		= 	frameDivisionX;
		emitterObj.frameDivisionY 		= 	frameDivisionY;
		emitterObj.animationSpeed 		= 	animationSpeed;
		emitterObj.animationLoop 		= 	animationLoop;
		emitterObj.animationUseSourceUVs 			= 	animationUseSourceUVs;
		emitterObj.animationBlendBetweenFrames 		= 	animationBlendBetweenFrames;
		emitterObj.useRandomColor 		= 	useRandomColor;
		emitterObj.useRandomGradient 	= 	useRandomGradient;
		emitterObj.randomColor1 		= 	h3d.Vector.fromArray(randomColor1);
		emitterObj.randomColor2 		= 	h3d.Vector.fromArray(randomColor2);
		emitterObj.randomGradient 		= 	randomGradient;

		emitterObj.init(params.randomSlots, this);

		#if editor
		if(propName == null || ["emitShape", "emitRadius", "emitAngle1", "emitAngle2", "emitWidth", "emitHeight"].indexOf(propName) >= 0)
			updateEmitShape(emitterObj);
		#end
	}

	#if (editor || editor_hl)
	function getVisibleParams() : Array<hrt.prefab.fx.EmitterHelper.ParamDef> {
		var params = emitterParams.copy();
		inline function removeParam(pname: String) {
			params.remove(params.find(p -> p.name == pname));
		}

		if(!emitShape.match(Circle)) {
			removeParam("emitRadius");
			removeParam("emitAngle1");
			removeParam("emitAngle2");
		}
		if(!emitShape.match(Rectangle)) {
			removeParam("emitWidth");
			removeParam("emitHeight");
		}

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

		if(!useRandomColor) {
			removeParam("useRandomGradient");
			removeParam("randomColor1");
			removeParam("randomColor2");
			removeParam("randomGradient");
		}
		else {
			if (useRandomGradient){
				removeParam("randomColor1");
				removeParam("randomColor2");
			} else {
				removeParam("randomGradient");
			}
		}

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

		return params;
	}

	static var REFRESH_PARAMS = ["emitShape", "emitType", "spriteType", "useRandomColor", "useRandomGradient"];
	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);
		EmitterEdit.edit(ctx, this, getVisibleParams(), REFRESH_PARAMS, (pname) -> {
			if (pname == "spriteType" && spriteType != SpriteType.SpriteSheet)
				spriteSheet = null;
		});
	}

	#if editor
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
