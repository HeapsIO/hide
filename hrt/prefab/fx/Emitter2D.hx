package hrt.prefab.fx;

import hrt.prefab.fx.Emitter;
import hrt.prefab.fx.Value;
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
		var evaluator = @:privateAccess emitter.evaluator;
		var t = hxd.Math.clamp(curLifeTime / lifeTime);

		m.identity();

		// POSITION
		if(evaluator.getPartOffset(idx, t, tmpVec)) {
			m.initTranslate(tmpVec.x, tmpVec.y);
		}

		// ROTATION
		if (evaluator.partRotation != VZero) {
			var r = evaluator.getPartRotation(idx, t) * Math.PI / 180.0;
			m.rotate(r);
		}

		// SCALE
		evaluator.getPartStretch(idx, t, tmpVec);
		tmpVec *= evaluator.getPartScale(idx, t);
		tmpVec *= emitter.curScaleMultiplier;
		m.scale(tmpVec.x, tmpVec.y);
	}

	function getCurrentAbsPos(m : h2d.col.Matrix, dt : Float) {
		var evaluator = @:privateAccess emitter.evaluator;
		var t = hxd.Math.clamp(curLifeTime / lifeTime);

		if (t == 0) {
			switch (emitter.prefab.emitShape) {
				case Circle:
					var radius = evaluator.getEmitRadius(emitter.curTime);
					var startAngle = evaluator.getEmitStartAngle(emitter.curTime) * hxd.Math.PI / 180;
					var endAngle = evaluator.getEmitEndAngle(emitter.curTime) * hxd.Math.PI / 180;

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
					var r = emitter.prefab.emitSurface ? radius : Math.sqrt(rsq);

					var posX = r * Math.cos(a);
					var posY = r * Math.sin(a);
					if (emitter.prefab.emitOrientation.match(Normal))
						m.initRotate(new Vector(posX, posY).getRotation());

					m.translate(posX, posY);

				case Rectangle:
					var width = evaluator.getEmitWidth(emitter.curTime);
					var height = evaluator.getEmitHeight(emitter.curTime);

					var posX = (emitter.rand.rand() - 0.5) * width;
					var posY = (emitter.rand.rand() - 0.5) * height;
					if (emitter.prefab.emitSurface) {
						if (emitter.rand.rand() < 0.5)
							posX = emitter.rand.rand() < 0.5 ? -width / 2 : width / 2;
						else
							posY = emitter.rand.rand() < 0.5 ? -height / 2 : height / 2;
					}

					if (emitter.prefab.emitOrientation.match(Normal))
						m.initRotate(new Vector(posX, posY).getRotation());

					m.translate(posX, posY);
			}

			// START LOCAL SPEED
			evaluator.getStartSpeed(idx, emitter.curTime, tmpVec);
			tmpVec.transform2x2(m);
			speed += tmpVec;

			// START WORLD SPEED
			evaluator.getStartWorldSpeed(idx, emitter.curTime, tmpVec);
			tmpVec.transform2x2(emitter.invTransform);
			speed += tmpVec;
		}

		// ACCELERATION
		if(evaluator.getPartAcceleration(idx, t, tmpVec)) {
			tmpVec.scale(dt);
			tmpVec.transform2x2(m);
			speed += tmpVec;
		}

		// WORLD ACCELERATION
		if(evaluator.getPartWorldAcceleration(idx, t, tmpVec)) {
			tmpVec.scale(dt);
			tmpVec.transform2x2(emitter.invTransform);
			speed += tmpVec;
		}

		tmpSpeed.set(speed.x, speed.y);

		// SPEED
		if(evaluator.getPartSpeed(idx, t, tmpVec)) {
			tmpVec.transform2x2(m);
			tmpSpeed += tmpVec;
		}

		// DAMPEN
		if (evaluator.partDampen != VZero) {
			var dampen = evaluator.getPartDampen(idx, t);
			var scale = Math.exp(dampen* -dt);
			speed.scale(scale);
		}


		// WORLD SPEED
		if(evaluator.getPartWorldSpeed(idx, t, tmpVec)) {
			tmpVec.transform2x2(emitter.invTransform);
			tmpSpeed += tmpVec;
		}

		// MAX VELOCITY
		if (evaluator.partMaxSpeed != VZero) {
			var maxVel = evaluator.getPartMaxSpeed(idx, t);
			var curVelSq = tmpSpeed.lengthSq();
			if (maxVel * maxVel < curVelSq) {
				tmpSpeed.normalize();
				tmpSpeed.scale(maxVel);
			}
		}

		m.translate(tmpSpeed.x * dt, tmpSpeed.y * dt);

		if (evaluator.partOrbitSpeed != VZero) {
			var orbitSpeed = evaluator.getPartOrbitSpeed(idx, t);

			var factorOverTime = emitter.curOrbitSpeedMultiplier;
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

		if (emitter.prefab.emitOrientation.match(Speed) && hxd.Math.abs(tmpSpeed.length()) > 0.0001) {
			var targetRotation = tmpSpeed.getRotation();
			basisAbsPos.rotate(targetRotation);
		}
	}
}

@:build(hrt.prefab.fx.EmitterMacros.buildEvaluator("hrt.prefab.fx.Emitter2D"))
class Emitter2DEvaluator extends Evaluator {}

class Emitter2DObject extends h2d.Object {
	public var particles : Array<Particle2DInstance> = [];
	public var batch : h2d.SpriteBatch;
	// built by the prefab, with a Value per param and animated property (EmitterMacros)
	public var evaluator : Emitter2DEvaluator;
	var rand : hxd.Rand;

	var prevTime : Float;
	var curTime = 0.;
	// the values of the over time settings at the current tick, shared by the particles
	var curScaleMultiplier = 1.;
	var curOrbitSpeedMultiplier = 1.;
	var countToEmit = 0.;
	var totalBurstCount = 0;
	var instanceCounter = 0;
	var animatedTexShader : h3d.shader.AnimatedTexture = null;

	public var prefab : Emitter2D;

	// Game overrides
	public var emitScale : Float = 1.0;
	public var lifeTimeScale : Float = 1.0;


	public var invTransform = new h2d.col.Matrix();

	public function new(?parent) {
		super(parent);

		batch = new h2d.SpriteBatch(h2d.Tile.fromColor(0xFF00FF, 10, 10), this);
		batch.hasRotationScale = true;
		rand = new hxd.Rand(0);
	}

	public function init(prefab: Emitter2D) {
		this.prefab = prefab;
		evaluator.allocRandom(prefab.maxCount, evaluator.randomSlots);
		evaluator.resetRandom(rand);

		if (animatedTexShader != null)
			batch.removeShader(animatedTexShader);

		if (prefab.spriteSheet != null) {
			var tex = hxd.res.Loader.currentInstance.load(prefab.spriteSheet).toTexture();
			var meanLifeTime = evaluator.getMean(evaluator.lifeTime, 0);
			animatedTexShader = new h3d.shader.AnimatedTexture(tex, prefab.frameDivisionX, prefab.frameDivisionY, prefab.frameCount, prefab.frameCount * prefab.animationCycles / meanLifeTime);
			animatedTexShader.useSourceUVs = prefab.animationUseSourceUVs;
			animatedTexShader.startTime = 0;
			animatedTexShader.loop = prefab.animationLoop;
			animatedTexShader.blendBetweenFrames = prefab.animationBlendBetweenFrames;
			animatedTexShader.setPriority(1);
			batch.addShader(animatedTexShader);
		}
	}

	public function setTime(time : Float, inCatchup : Bool = false) {
		prevTime = curTime;
		curTime = (time * prefab.timeScale + prefab.warmUpTime) - prefab.delay;

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
				setTime(t - prefab.warmUpTime + prefab.delay, true);
			}
		}
		else if (dt > 0) {
			tick(dt);
		}
	}

	inline function getBurstCount() {
		return EmitterHelper.getBurstCount(evaluator, evaluator.burstParticleCount, curTime, totalBurstCount, prefab.seed);
	}

	inline function getRate() {
		return EmitterHelper.getRate(evaluator, evaluator.emitRate, curTime, prefab.emitRateChangeTime, prefab.seed);
	}

	function tick(dt : Float) {
		curScaleMultiplier = evaluator.getScaleMultiplier(curTime);
		curOrbitSpeedMultiplier = evaluator.getOrbitSpeedMultiplier(curTime);

		switch (prefab.emitType) {
			case Infinity:
				var emitTarget = getRate() * hxd.Math.clamp(emitScale) * dt;
				countToEmit += hxd.Math.min(prefab.maxCount - particles.length, emitTarget);
				var t = hxd.Math.floor(countToEmit);
				countToEmit -= t;
				doEmit(t);

			case Duration:
				var emitTarget = getRate() * hxd.Math.clamp(emitScale) * dt;
				countToEmit += curTime >= prefab.emitDuration ? 0 : hxd.Math.min(prefab.maxCount - particles.length, emitTarget);
				var t = hxd.Math.floor(countToEmit);
				countToEmit -= t;
				doEmit(t);

			case Burst:
				if (prefab.burstInterval > 0) {
					var burstTarget = hxd.Math.min(prefab.burstCount, 1 + hxd.Math.floor(curTime / prefab.burstInterval));
					while (totalBurstCount < burstTarget) {
						var emitTarget = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - particles.length, getBurstCount()));
						doEmit(emitTarget);
						totalBurstCount++;
					}
				}

			case BurstDuration:
				if (curTime < prefab.emitDuration) {
					var emitTarget = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - particles.length, getBurstCount()));
					doEmit(emitTarget);
					totalBurstCount++;
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
			part.lifeTime = evaluator.getLifeTime(part.idx, curTime) * lifeTimeScale;
			this.particles.push(part);
			instanceCounter = (instanceCounter + 1) % prefab.maxCount;
		}
	}

	function reset() {
		particles = [];
		batch.clear();
		countToEmit = 0;
		totalBurstCount = 0;
		instanceCounter = 0;

		rand.init(prefab.seed);
		evaluator.resetRandom(rand);
	}

	static function colorTile( c : Int ) {
		return h2d.Tile.fromColor(c, 10, 10, (c >>> 24) / 255);
	}

	function getTile() {
		var t = h2d.Tile.fromColor(0xFF00FF, 10, 10);
		switch (prefab.spriteType) {
			case Color:
				switch (prefab.randomColorMode) {
					case None:
						t = colorTile(prefab.color);
					case Colors:
						var c = h3d.Vector4.fromColor(prefab.randomColor1);
						c.lerp(c, h3d.Vector4.fromColor(prefab.randomColor2), rand.rand());
						t = colorTile(c.toColor());
					case Gradient:
						t = colorTile(Gradient.evalData(prefab.randomGradient, rand.rand()).toColor());
				}
			case Texture:
				t = h2d.Tile.fromTexture(hxd.res.Loader.currentInstance.load(prefab.texture).toTexture());
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
@:build(hrt.prefab.fx.EmitterMacros.build("hrt.prefab.fx.Emitter2D.Emitter2DEvaluator"))
class Emitter2D extends Object2D implements hrt.prefab.fx.EmitterParam.IEmitter {

	@:group("Properties")
	@:s @:range(0, 1) @:disp("Time Scale", "Time multiplier of the simulation")
	public var timeScale : Float = 1.0;
	@:s @:range(0, 10) @:disp("Start Delay", "Time before the start of the emitter, in seconds")
	public var delay : Float = 0.0;
	@:s @:range(0, 1) @:disp("Warm Up", "Time simulated before the start, in seconds: the emitter starts already filled")
	public var warmUpTime : Float = 0.0;
	@:s @:range(0, 100) @:disp("Seed", "Seed of the random values of the emitter")
	public var seed : Int = 0;

	@:group("Emission")
	@:s @:disp("Type", "Infinity: emits at its rate. Duration: emits at its rate during a duration. Burst / Burst Duration: groups of particles at regular intervals")
	public var emitType : EmitType = EmitType.Infinity;
	@:s @:range(0, 10.0) @:disp("Duration", "Emission duration, in seconds")
	public var emitDuration : Float = 1.0;
	@:param(PFloat(0, 100), Emission, 5.) @:disp("Rate", "Number of particles emitted per second. A Range changes it at random between min and max, every Rate Change Time")
	public var emitRate : ParamMode;
	@:s @:range(0.01, 5.0) @:disp("Rate Change Time", "Random rate: every this many seconds a new random rate is picked between min and max, and the rate goes to it during this time")
	public var emitRateChangeTime : Float = 1.0;
	@:s @:range(1, 10) @:disp("Burst Count", "Number of bursts")
	public var burstCount : Int = 1;
	@:s @:range(0, 1.0) @:disp("Burst Interval", "Time between two bursts, in seconds")
	public var burstInterval : Float = 1.0;
	@:param(PFloat(1, 10), Emission, 1.) @:disp("Particles Per Burst", "Number of particles emitted by each burst. A Range draws it for each burst, between min and max")
	public var burstParticleCount : ParamMode;
	@:s @:range(0, 100) @:disp("Max Count", "Maximum number of particles alive at the same time: no particle is emitted beyond")
	public var maxCount : Int = 20;
	@:param(PFloat(0, 10), Spawn, 1.) @:disp("Lifetime", "Life duration of the particle, in seconds")
	public var lifeTime : ParamMode;

	@:group("Emit Shape")
	@:s @:disp("Shape", "Area in which the particles are emitted")
	public var emitShape : Emit2DShape = Emit2DShape.Circle;
	@:s @:range(0, 360.0) @:animate @:disp("Radius", "Radius of the circle")
	public var emitRadius : Float = 20.0;
	@:s @:range(0, 360.0) @:animate @:disp("Start Angle", "Start angle of the circle arc, in degrees")
	public var emitStartAngle : Float = 20.0;
	@:s @:range(0, 360.0) @:animate @:disp("End Angle", "End angle of the circle arc, in degrees")
	public var emitEndAngle : Float = 40.0;
	@:s @:range(0, 10.0) @:animate @:disp("Width", "Width of the rectangle")
	public var emitWidth : Float = 1.0;
	@:s @:range(0, 10.0) @:animate @:disp("Height", "Height of the rectangle")
	public var emitHeight : Float = 1.0;
	@:s @:disp("Surface", "Emits on the outline of the shape instead of inside it")
	public var emitSurface : Bool = false;
	@:s @:disp("Orientation", "Initial orientation of the particles: the emitter one, the normal of the shape, their speed, or random")
	public var emitOrientation : Orientation = Orientation.Forward;

	@:group("Particle Movement")
	@:param(PVec(2, -10, 10), Spawn) @:disp("Start Speed", "Initial speed in the emitter orientation, set at the spawn of the particle")
	public var startSpeed : ParamVec2;
	@:param(PVec(2, -10, 10), Spawn) @:disp("Start World Speed", "Initial speed in world space, set at the spawn of the particle")
	public var startWorldSpeed : ParamVec2;
	@:param(PVec(2, -10, 10), Particle) @:disp("Constant Speed", "Speed in the emitter orientation, added to the velocity without being accumulated")
	public var partSpeed : ParamVec2;
	@:param(PVec(2, -10, 10), Particle) @:disp("Constant World Speed", "Speed in world space, added to the velocity without being accumulated")
	public var partWorldSpeed : ParamVec2;
	@:param(PVec(2, -10, 10), Particle) @:disp("Acceleration", "Acceleration in the emitter orientation, accumulated in the velocity")
	public var partAcceleration : ParamVec2;
	@:param(PVec(2, -10, 10), Particle) @:disp("World Acceleration", "Acceleration in world space (gravity, wind...), accumulated in the velocity")
	public var partWorldAcceleration : ParamVec2;
	@:param(PFloat(-360, 360), Particle) @:disp("Orbit Speed", "Rotation speed around the emitter, in degrees per second")
	public var partOrbitSpeed : ParamMode;
	@:s @:range(0, 2) @:animate @:disp("Orbit Speed Multiplier", "Multiplier of the orbit speed of all the particles, animated over the emitter time")
	public var orbitSpeedMultiplier : Float = 1;

	@:group("Limit Velocity")
	@:param(PFloat(0, 10), Particle) @:disp("Dampen", "Damping of the accumulated velocity (start speed and accelerations), per second")
	public var partDampen : ParamMode;
	@:param(PFloat(0, 10), Particle) @:disp("Max Speed", "Maximum speed of the particle")
	public var partMaxSpeed : ParamMode;

	@:group("Particle Transform")
	@:param(PVec(2, -10, 10), Particle) @:disp("Offset", "Offset of the particle position, without effect on its movement")
	public var partOffset : ParamVec2;
	@:param(PFloat(0, 360), Particle) @:disp("Rotation", "Rotation of the particle, in degrees")
	public var partRotation : ParamMode;
	@:param(PFloat(0, 2), Particle, 1.) @:disp("Scale", "Uniform scale of the particle")
	public var partScale : ParamMode;
	@:s @:range(0, 2) @:animate @:disp("Scale Multiplier", "Multiplier of the scale of all the particles, animated over the emitter time")
	public var scaleMultiplier : Float = 1;
	@:param(PVec(2, 0, 2), Particle, [1., 1.]) @:disp("Stretch", "Scale of the particle on each of its axes")
	public var partStretch : ParamVec2;

	@:group("Rendering")
	@:s @:disp("Sprite Type", "Drawing of the particles: a plain color, a texture or a sprite sheet")
	public var spriteType : SpriteType = SpriteType.Color;
	@:s @:t(PColor) @:disp("Color", "Color of the particles")
	public var color : Int = 0xFF000000;
	@:s @:disp("Texture", "Texture of the particles")
	public var texture : String = "";
	@:s @:disp("Random Color", "Gives each particle a random color instead of the color, taken between two colors or in a gradient")
	public var randomColorMode : RandomColorMode = RandomColorMode.None;
	@:s @:t(PColor) @:disp("Color 1", "First bound of the random color")
	public var randomColor1 : Int = 0xFF000000;
	@:s @:t(PColor) @:disp("Color 2", "Second bound of the random color")
	public var randomColor2 : Int = 0xFFFFFFFF;
	@:s @:disp("Gradient", "Gradient in which the random color is taken")
	public var randomGradient : GradientData;

	@:group("Sprite Sheet Animation")
	@:s @:t(PFile(["jpg", "png"])) @:disp("Sheet", "Texture containing the frames of the animation")
	public var spriteSheet : String;
	@:s @:range(0) @:disp("Frames", "Number of frames of the animation")
	public var frameCount : Int = 0;
	@:s @:range(1) @:disp("Divisions X", "Number of columns of the sheet")
	public var frameDivisionX : Int = 1;
	@:s @:range(1) @:disp("Divisions Y", "Number of rows of the sheet")
	public var frameDivisionY : Int = 1;
	@:s @:range(0, 2.0) @:disp("Cycles", "Number of times the animation is played during the life of a particle")
	public var animationCycles : Float = 1.0;
	@:s @:disp("Loop", "Loops the animation during the life of the particle")
	public var animationLoop : Bool = true;
	@:s @:disp("Use Source UV", "Keeps the UVs of the sprite inside each frame")
	public var animationUseSourceUVs : Bool = true;
	@:s @:disp("Blend Frames", "Blends two consecutive frames for a smooth animation")
	public var animationBlendBetweenFrames : Bool = true;

	#if editor
	var graphics : h2d.Graphics;
	#end

	override function save() {
		var data = super.save();
		saveParams(data);
		if( randomColorMode != RandomColorMode.Gradient )
			Reflect.deleteField(data, "randomGradient");
		if( !FX.inFXData(this) )
			data.version = FX.VERSION;
		return data;
	}

	override function load( obj : Dynamic ) {
		// an emitter out of any FX (in a prefab) is the root of its FX data
		if( !FX.inFXData(this) )
			FX.checkVersion(this, obj);
		super.load(obj);
		loadParams(obj);
		if( randomGradient == null && randomColorMode == RandomColorMode.Gradient )
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
		emitterObj.evaluator = makeEvaluator();
		emitterObj.blendMode  			= 	this.blendMode;
		emitterObj.batch.blendMode      =   this.blendMode;

		emitterObj.init(this);

		#if editor
		if(propName == null || ["emitShape", "emitRadius", "emitStartAngle", "emitEndAngle", "emitWidth", "emitHeight"].indexOf(propName) >= 0)
			updateEmitShape(emitterObj);
		#end
	}

	#if (editor || editor_hl)
	function getHiddenFields() : Array<String> {
		var hidden = [];
		inline function hide(name: String)
			hidden.push(name);

		if(!emitShape.match(Circle)) {
			hide("emitRadius");
			hide("emitStartAngle");
			hide("emitEndAngle");
		}
		if(!emitShape.match(Rectangle)) {
			hide("emitWidth");
			hide("emitHeight");
		}

		if (spriteType != SpriteType.Color) {
			hide("color");
			hide("randomColorMode");
		}
		if (spriteType != SpriteType.Texture) {
			hide("texture");
		}
		if (spriteType != SpriteType.SpriteSheet) {
			hide("spriteSheet");
			hide("frameCount");
			hide("frameDivisionX");
			hide("frameDivisionY");
			hide("animationCycles");
			hide("animationLoop");
			hide("animationUseSourceUVs");
			hide("animationBlendBetweenFrames");
		}

		if (spriteType != SpriteType.Color || randomColorMode != RandomColorMode.Colors) {
			hide("randomColor1");
			hide("randomColor2");
		}
		if (spriteType != SpriteType.Color || randomColorMode != RandomColorMode.Gradient)
			hide("randomGradient");

		switch (emitType) {
			case Infinity:
				hide("burstCount");
				hide("burstInterval");
				hide("burstParticleCount");
				hide("emitDuration");
			case Duration:
				hide("burstCount");
				hide("burstInterval");
				hide("burstParticleCount");
			case Burst:
				hide("emitDuration");
				hide("emitRate");
			case BurstDuration:
				hide("burstCount");
				hide("emitRate");
		}
		// read only by a random rate, which bursts do not use
		var randomRate = switch (getMode("emitRate", 0)) {
			case Range(_), RandomCurve(_), CurveRange: true;
			case null, _: false;
		}
		if (!randomRate || emitType == Burst || emitType == BurstDuration)
			hide("emitRateChangeTime");

		return hidden;
	}

	static var REFRESH_PARAMS = ["emitShape", "emitType", "spriteType", "randomColorMode"];
	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		function onChange(pname: String, isTemp: Bool) {
			if (pname == "randomColorMode")
				randomGradient = randomColorMode == RandomColorMode.Gradient ? Gradient.getDefaultGradientData() : null;
			if (pname == "spriteType" && spriteType != SpriteType.SpriteSheet)
				spriteSheet = null;
			ctx.rebuildPrefab(this);
			if (!isTemp && REFRESH_PARAMS.contains(pname))
				ctx.rebuildInspector();
		}

		EmitterHelper.edit(ctx, this, getHiddenFields(), onChange);
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
		switch(emitShape) {
			case Circle:
				var radA1 = e.evaluator.getFloat(e.evaluator.emitStartAngle, 0) * hxd.Math.PI / 180;
				var radA2 = e.evaluator.getFloat(e.evaluator.emitEndAngle, 0) * hxd.Math.PI / 180;
				graphics.drawPie(0, 0, e.evaluator.getFloat(e.evaluator.emitRadius, 0), radA1, radA2 - radA1);
			case Rectangle:
				var width = e.evaluator.getFloat(e.evaluator.emitWidth, 0);
				var height = e.evaluator.getFloat(e.evaluator.emitHeight, 0);
				graphics.drawRect(-width / 2, -height / 2, width, height);
		}
	}
	#end

	static var _ = Prefab.register("emitter2D", Emitter2D);
}
