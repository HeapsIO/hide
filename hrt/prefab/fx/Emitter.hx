package hrt.prefab.fx;
import hrt.shader.BaseEmitter;
import hrt.impl.Gradient;
import hrt.prefab.l3d.Polygon;
import hrt.prefab.Curve;
import hrt.prefab.fx.BaseFX.ShaderAnimation;
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

enum AlignLockAxis {
	X;
	Y;
	Z;
	ScreenZ;  // Screen-facing flat polygons rotating around Z
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

enum EmitType {
	Infinity;
	InfinityRandom;
	Duration;
	Burst;
	BurstDuration;
}

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?instance: Bool,
	?groupName: String
}

@:publicFields
class InstanceDef {
	var localSpeed: Value;
	var worldSpeed: Value;
	var startSpeed: Value;
	var startWorldSpeed: Value;
	var orbitSpeed: Value;
	var acceleration: Value;
	var worldAcceleration: Value;
	var localOffset: Value;
	var scale: Value;
	var stretch: Value;
	var stretchVelocity: Value;
	var rotation: Value;
	var dampen: Value;
	var maxVelocity : Value;
	public function new() { }
}

typedef ShaderAnims = Array<ShaderAnimation>;
typedef PartArray = #if (hl_ver >= version("1.13.0")) hl.CArray<ParticleInstance> #else Array<ParticleInstance> #end;
typedef Single = #if (hl_ver >= version("1.13.0")) hl.F32 #else Float #end;

@:publicFields @:struct
private class ParticleInstance {
	var prev : ParticleInstance;
	var next : ParticleInstance;

	var x : Single;
	var y : Single;
	var z : Single;
	var scaleX : Single;
	var scaleY : Single;
	var scaleZ : Single;

	var trail : hrt.prefab.l3d.Trails.TrailHead;
	var trailGeneration : Int = 0;

	#if (hl_ver >= version("1.13.0"))
	@:packed var speedAccumulation(default, never) : SVector3;
	@:packed var qRot(default, never) : SVector4;
	@:packed var absPos(default, never) : SMatrix4;  // Needed for sortZ
	@:packed var emitOrientation(default, never) : SMatrix3;
	#else
	var speedAccumulation(default, never) = new SVector3();
	var qRot(default, never) = new SVector4();
	var absPos(default, never) = new SMatrix4();
	var emitOrientation(default, never) = new SMatrix3();
	#end

	var colorMult : Int;
	var idx : hxd.impl.UInt16;
	var startFrame : hxd.impl.UInt16;
	var life : Single;
	var lifeTime : Single;
	var random : Single;
	var distToCam : Single;
	var startTime : Single;

	inline static var REMOVED_IDX : hxd.impl.UInt16 = -1;

	function new() { }

	function load(p: ParticleInstance) {
		x = p.x;
		y = p.y;
		z = p.z;
		scaleX = p.scaleX;
		scaleY = p.scaleY;
		scaleZ = p.scaleZ;

		speedAccumulation.load(p.speedAccumulation.toVector());
		qRot.load(p.qRot.toVector());
		absPos.load(p.absPos.toMatrix());
		emitOrientation.load(p.emitOrientation.toMatrix());

		colorMult = p.colorMult;
		idx = p.idx;
		startFrame = p.startFrame;
		life = p.life;
		lifeTime = p.lifeTime;
		random = p.random;
		distToCam = p.distToCam;
		startTime = p.startTime;
		prev = p.prev;
		next = p.next;
		trail = p.trail;
		trailGeneration = p.trailGeneration;
	}

	function init(idx: Int, emitter: EmitterObject) {
		x = 0.0;
		y = 0.0;
		z = 0.0;
		scaleX = 1.0;
		scaleY = 1.0;
		scaleZ = 1.0;

		colorMult = -1;
		if(this.idx != REMOVED_IDX) throw this.idx;
		this.idx = idx;
		speedAccumulation.load(new h3d.Vector());
		life = 0;
		lifeTime = 0;
		startFrame = 0;
		random = emitter.random.rand();

		if (emitter.trails != null) {
			trail = emitter.trails.allocTrail();
			trailGeneration = trail.generation;
		}
	}

	static var tmpRot = new h3d.Vector();
	static var tmpOffset = new h3d.Vector();
	static var tmpScale = new h3d.Vector();
	static var tmpLocalSpeed = new h3d.Vector();
	static var tmpWorldSpeed = new h3d.Vector();
	static var tmpSpeedAccumulation = new h3d.Vector();
	static var tmpGroundNormal = new h3d.Vector(0,0,1);
	static var tmpSpeed = new h3d.Vector();
	static var tmpMat = new h3d.Matrix();
	static var tmpMat2 = new h3d.Matrix();
	static var tmpCamRotAxis = new h3d.Vector();
	static var tmpCamAlign = new h3d.Vector();
	static var tmpCamVec = new h3d.Vector();
	static var tmpCamVec2 = new h3d.Vector();
	static var tmpQuat = new h3d.Quat();


	inline function add( v1 : h3d.Vector, v2 : h3d.Vector ) {
		v1.x += v2.x;
		v1.y += v2.y;
		v1.z += v2.z;
	}

	inline function sub( v1 : h3d.Vector, v2 : h3d.Vector ) {
		v1.x -= v2.x;
		v1.y -= v2.y;
		v1.z -= v2.z;
	}

	inline function cross( v1 : h3d.Vector, v2 : h3d.Vector ) {
		v1.x -= v1.y * v2.z - v1.z * v2.y;
		v1.y -= v1.z * v2.x - v1.x * v2.z;
		v1.z -= v1.x * v2.y - v1.y * v2.x;
		v1.w = 1.0;
	}

	inline function getPosition() { return new h3d.Vector(x,y,z); }
	inline function setPosition(x, y, z) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	inline function setScale( x, y, z ) {
		scaleX = x;
		scaleY = y;
		scaleZ = z;
	}

	function updateAbsPos(emitter: EmitterObject) {
		var qRot = qRot.toQuat();

		switch( emitter.alignMode ) {
			case Screen|Axis:
				qRot.load(emitter.screenQuat);
			default:
		}

		var absPos = tmpMat;
		var localMat = tmpMat2;

		inline qRot.toMatrix(absPos);
		absPos._11 *= scaleX;
		absPos._12 *= scaleX;
		absPos._13 *= scaleX;
		absPos._21 *= scaleY;
		absPos._22 *= scaleY;
		absPos._23 *= scaleY;
		absPos._31 *= scaleZ;
		absPos._32 *= scaleZ;
		absPos._33 *= scaleZ;
		absPos._41 = x;
		absPos._42 = y;
		absPos._43 = z;
		absPos.multiply3x4inline(absPos, emitter.parentTransform);

		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);

		var evaluator = emitter.evaluator;

		//SCALE
		var def = emitter.instDef;
		var scaleVec = evaluator.getVector(idx, def.stretch, t, tmpScale);
		scaleVec.scale3(evaluator.getFloat(idx, def.scale, t));
		localMat.initScale(scaleVec.x, scaleVec.y, scaleVec.z);

		// ROTATION
		if(def.rotation != VZero) {
			var rot = evaluator.getVector(idx, def.rotation, t, tmpRot);
			rot.scale3(Math.PI / 180.0);
			localMat.rotate(rot.x, rot.y, rot.z);
		}

		//OFFSET
		if(def.localOffset != VZero) {
			var offset = evaluator.getVector(idx, def.localOffset, t, tmpOffset);
			localMat.tx += offset.x;
			localMat.ty += offset.y;
			localMat.tz += offset.z;
		}

		if(emitter.baseEmitMat != null)
			localMat.multiply(emitter.baseEmitMat, localMat);

		absPos.multiply(localMat, absPos);
		this.absPos.load(absPos);
	}

	function update(emitter : EmitterObject, dt : Float) {
		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);
		tmpSpeed.set(0,0,0);

		var def = emitter.instDef;
		var evaluator = emitter.evaluator;
		var emitOrientation = emitOrientation.toMatrix();
		var speedAccumulation = this.speedAccumulation.toVector();

		if( life == 0 ) {
			// START LOCAL SPEED
			evaluator.getVector(idx, def.startSpeed, 0.0, tmpSpeedAccumulation);
			tmpSpeedAccumulation.transform3x3(emitOrientation);
			add(speedAccumulation, tmpSpeedAccumulation);
			// START WORLD SPEED
			evaluator.getVector(idx, def.startWorldSpeed, 0.0, tmpSpeedAccumulation);
			tmpSpeedAccumulation.transform3x3(emitter.invTransform);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		// ACCELERATION
		if(def.acceleration != VZero) {
			evaluator.getVector(idx, def.acceleration, t, tmpSpeedAccumulation);
			tmpSpeedAccumulation.scale3(dt);
			tmpSpeedAccumulation.transform3x3(emitOrientation);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		// WORLD ACCELERATION
		if(def.worldAcceleration != VZero) {
			evaluator.getVector(idx, def.worldAcceleration, t, tmpSpeedAccumulation);
			tmpSpeedAccumulation.scale3(dt);
			if(emitter.simulationSpace == Local)
				tmpSpeedAccumulation.transform3x3(emitter.invTransform);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		add(tmpSpeed, speedAccumulation);

		// SPEED
		if(def.localSpeed != VZero) {
			evaluator.getVector(idx, def.localSpeed, t, tmpLocalSpeed);
			tmpLocalSpeed.transform3x3(emitOrientation);
			add(tmpSpeed, tmpLocalSpeed);
		}

		// DAMPEN
		if (def.dampen != VZero) {
			var dampen = evaluator.getFloat(idx, def.dampen, t);
			var scale = Math.exp(dampen* -dt);
			speedAccumulation.scale3(scale);
		}


		// WORLD SPEED
		if(def.worldSpeed != VZero) {
			evaluator.getVector(idx, def.worldSpeed, t, tmpWorldSpeed);
			if(emitter.simulationSpace == Local)
				tmpWorldSpeed.transform3x3(emitter.invTransform);
			add(tmpSpeed, tmpWorldSpeed);
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

		if(emitter.simulationSpace == World) {
			tmpSpeed.x *= emitter.worldScale.x;
			tmpSpeed.y *= emitter.worldScale.y;
			tmpSpeed.z *= emitter.worldScale.z;
		}

		// STRETCH VELOCITY
		if (def.stretchVelocity != VZero) {
			var s = evaluator.getFloat(idx, def.stretchVelocity, t);
			var up = tmpCamVec2;
			up.set(absPos._11, absPos._12, absPos._13);
			var sx = hxd.Math.abs(tmpSpeed.dot(up));
			sx = hxd.Math.min(sx, 0.25);

			absPos._11 *= s * sx;
			absPos._12 *= s * sx;
			absPos._13 *= s * sx;
			absPos._21 *= s * 1.0/sx;
			absPos._22 *= s * 1.0/sx;
			absPos._23 *= s * 1.0/sx;
			absPos._31 *= s * 1.0/sx;
			absPos._32 *= s * 1.0/sx;
			absPos._33 *= s * 1.0/sx;
		}

		x += tmpSpeed.x * dt;
		y += tmpSpeed.y * dt;
		z += tmpSpeed.z * dt;

		if(def.orbitSpeed != VZero) {
			evaluator.getVector(idx, def.orbitSpeed, t, tmpLocalSpeed);
			tmpMat.initRotation(tmpLocalSpeed.x * dt, tmpLocalSpeed.y * dt, tmpLocalSpeed.z * dt);
			// Rotate in emitter space and convert back to world space
			var parentAbsPos = emitter.parentTransform;
			var prevPos = getPosition();
			var pos = prevPos.add(parentAbsPos.getPosition());
			pos.w = 1;
			pos.transform3x4(emitter.getInvPos());
			pos.transform3x3(tmpMat);
			pos.transform3x4(emitter.getAbsPos());
			x = pos.x - parentAbsPos.tx;
			y = pos.y - parentAbsPos.ty;
			z = pos.z - parentAbsPos.tz;

			// Take transform into account into local speed
			var delta = getPosition().sub(prevPos);
			delta.scale(1 / dt);
			add(tmpSpeed, delta);
		}

		this.speedAccumulation.load(speedAccumulation);


		if(emitter.emitOrientation == Speed && tmpSpeed.lengthSq() > 0.01) {
			var qRot = qRot.toQuat();
			inline qRot.initDirection(tmpSpeed);
			this.qRot.loadQuat(qRot);
		}
	}
}

@:allow(hrt.prefab.fx.ParticleInstance)
@:allow(hrt.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public var instDef : InstanceDef;

	public var particles : PartArray;
	public var listHead : ParticleInstance;
	public var batch : h3d.scene.MeshBatch;
	public var shaderAnims : ShaderAnims;

	public var isSubEmitter : Bool = false;
	public var parentEmitter : EmitterObject = null;
	public var enable : Bool;

	public var startTime = 0.0;
	public var catchupSpeed = 4; // Use larger ticks when catching-up to save calculations
	public var totalBurstCount : Int = 0; // Keep track of burst count
	#if !editor
	public var maxCatchupWindow = 0.5; // How many seconds max to simulate when catching up
	#end

	public var emitterPrefab : Emitter;

	// RANDOM
	public var seedGroup = 0;
	// OBJECTS
	public var particleTemplate : hrt.prefab.Object3D;
	public var subEmitterTemplates : Array<Emitter>;
	public var subEmitters : Array<EmitterObject>;
	public var trails : hrt.prefab.l3d.Trails.TrailObj;
	public var trailsTemplate : hrt.prefab.l3d.Trails;
	// LIFE
	public var lifeTime = 2.0;
	public var lifeTimeRand = 0.0;
	public var speedFactor = 1.0;
	public var warmUpTime = 0.0;
	// EMIT PARAMS
	public var emitOrientation : Orientation = Forward;
	public var simulationSpace : SimulationSpace = Local;
	public var emitType : EmitType = Infinity;
	public var burstCount : Int = 1;
	public var burstParticleCount : Int = 5;
	public var burstDelay : Float = 1.0;
	public var emitDuration : Float = 1.0;
	public var emitRate : Value;
	public var emitRateMin : Value;
	public var emitRateMax : Value;
	public var emitRateChangeDelay : Float = 1.0;
	public var emitRateCurrent : Null<Float>;
	public var emitRateChange : Float = 0.0;
	public var emitRateLastChangeTime : Float = 0.0;
	public var maxCount = 20;
	public var enableSort = true;
	// EMIT SHAPE
	public var emitShape : EmitShape = Cylinder;
	public var emitAngle : Float = 0.0;
	public var emitRad1 : Float = 1.0;
	public var emitRad2 : Float = 1.0;
	public var emitSurface : Bool = false;
	// ANIMATION
	public var spriteSheet : String;
	public var frameCount : Int = 0;
	public var frameDivisionX : Int = 1;
	public var frameDivisionY : Int = 1;
	public var animationSpeed : Float = 1;
	public var animationLoop : Bool = true;
	// ALIGNMENT
	public var alignMode : AlignMode;
	public var alignLockAxis : AlignLockAxis;
	// COLLISION
	public var elasticity : Float = 1.0;
	public var killOnCollision : Float = 0.0;
	public var useCollision : Bool = false;
	// RANDOM COLOR
	public var useRandomColor : Bool = false;
	public var useRandomGradient : Bool = false;
	public var randomColor1 : h3d.Vector;
	public var randomColor2 : h3d.Vector;
	public var randomGradient : GradientData;

	public var invTransform = new h3d.Matrix();
	public var screenQuat = new h3d.Quat();
	public var worldScale = new h3d.Vector(1,1,1);

	var random: hxd.Rand;
	var randomSeed = 0;
	var context : hrt.prefab.Context;
	var emitCount = 0;
	var emitTarget = 0.0;
	var curTime = 0.0;
	var evaluator : Evaluator;
	var numInstances = 0;
	var instanceCounter = 0;
	var baseEmitterShader : hrt.shader.BaseEmitter = null;
	var animatedTextureShader : h3d.shader.AnimatedTexture = null;
	var colorMultShader : h3d.shader.ColorMult = null;

	var parentTransform = new h3d.Matrix();
	var baseEmitMat : h3d.Matrix;
	var randomValues : Array<Float>;
	var randSlots : Int;

	public function new(?parent) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
	}

	function makeShaderInstance(prefab: hrt.prefab.Shader, ctx:Context):Context {
		ctx = ctx.clone(prefab);
		var shader = prefab.makeShader(ctx);
		if( shader == null )
			return ctx;
		ctx.custom = shader;
		prefab.updateInstance(ctx);
		ctx.local3d = null;  // prevent ContextShared.getSelfObject from incorrectly reporting object
		return ctx;
	}

	function init(randSlots: Int, prefab: Emitter) {
		this.emitterPrefab = prefab;
		this.randSlots = randSlots;

		if( batch != null )
			batch.remove();

		baseEmitMat = null;
		var meshPrimitive : h3d.prim.MeshPrimitive = null;
		var meshMaterial : h3d.mat.Material = null;
		if (particleTemplate != null) {
			baseEmitMat = particleTemplate.getTransform();
			if(baseEmitMat.isIdentityEpsilon(0.01))
				baseEmitMat = null;

			var template = particleTemplate.makeInstance(context);
			var mesh = Std.downcast(template.local3d, h3d.scene.Mesh);
			if( mesh == null ) {
				for( i in 0...template.local3d.numChildren ) {
					mesh = Std.downcast(template.local3d.getChildAt(i), h3d.scene.Mesh);
					if( mesh != null ) {
						break;
					}
				}
			}

			if (mesh != null) {
				meshPrimitive = Std.downcast(mesh.primitive, h3d.prim.MeshPrimitive);
				meshMaterial = mesh.material;
				mesh.remove();
			}

			template.shared.contexts.remove(particleTemplate);
			template.local3d.remove();
			template.local3d = null;
		}

		if (meshPrimitive == null ) {
			var shape : Shape = Quad(0);
			var cache = Polygon.getPrimCache();
			meshPrimitive = cache.get(shape);
			if(meshPrimitive == null)
				meshPrimitive = Polygon.createPrimitive(shape);
		}

		if(meshPrimitive != null ) {

			batch = new h3d.scene.MeshBatch(meshPrimitive, meshMaterial, null);
			addChildAt(batch, 0);
			batch.name = "emitter";
			batch.calcBounds = false;

			// Setup mats.
			// Should we do this manually here or make a recursive makeInstance on the template?
			var materials = emitterPrefab.getAll(hrt.prefab.Material);
			for(mat in materials) {

				// Remove materials that are not directly parented to this emitter
				var p = mat.parent;
				while (p != null && Std.downcast(p, Emitter) == null) {
					p = p.parent;
				}

				if (this.emitterPrefab == p) {
					if(mat.enabled) {
						var ctx = mat.makeInstance(context);
						ctx.local3d = null;
					}
				}
			}

			// Setup shaders
			shaderAnims = [];
			var shaders = emitterPrefab.getAll(hrt.prefab.Shader);
			for( shader in shaders ) {
				// Remove shaders that are not directly parented to this emitter
				var p = shader.parent;
				while (p != null && Std.downcast(p, Emitter) == null) {
					p = p.parent;
				}
				if (this.emitterPrefab == p) {
					if( !shader.enabled ) continue;
					var shCtx = makeShaderInstance(shader, context);
					if( shCtx == null ) continue;
	
					//shCtx.local3d = null; // Prevent shader.iterMaterials from adding our objet to the list incorectly
	
					hrt.prefab.fx.BaseFX.getShaderAnims(shCtx, shader, shaderAnims);
					var shader = Std.downcast(shCtx.custom, hxsl.Shader);
					batch.material.mainPass.addShader(shader);
				}
			}

			// Animated textures animations
			var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
			if( frameCount > 1 && spriteSheet != null ) {
				var tex = hxd.res.Loader.currentInstance.load(spriteSheet).toTexture();
				animatedTextureShader = new h3d.shader.AnimatedTexture(tex, frameDivisionX, frameDivisionY, frameCount, frameCount * animationSpeed / lifeTime);
				animatedTextureShader.startTime = startTime;
				animatedTextureShader.loop = animationLoop;
				animatedTextureShader.setPriority(1);
				batch.material.mainPass.addShader(animatedTextureShader);
			}

			baseEmitterShader = new hrt.shader.BaseEmitter();
			batch.material.mainPass.addShader(baseEmitterShader);

			if(useRandomColor) {
				colorMultShader = new h3d.shader.ColorMult();
				batch.material.mainPass.addShader(colorMultShader);
			}

		}

		particles = #if (hl_ver >= version("1.13.0")) hl.CArray.alloc(ParticleInstance, maxCount) #else [for(i in 0...maxCount) new ParticleInstance()] #end;
		randomValues = [for(i in 0...(maxCount * randSlots)) 0];
		evaluator = new Evaluator(randomValues, randSlots);
		reset();
	}

	override function onRemove() {
		if (subEmitters != null) {
			for (sub in subEmitters) {
				sub.remove();
			}
		}
		super.onRemove();
	}

	public function reset() {
		numInstances = 0;
		enable = true;
		random.init(randomSeed);
		curTime = 0.0;
		emitCount = 0;
		emitTarget = 0;
		totalBurstCount = 0;
		listHead = null;

		if(randomValues != null) {
			for(i in 0...randomValues.length)
				randomValues[i] = random.srand();
		}

		if(particles != null) {
			for(p in particles)
				p.idx = ParticleInstance.REMOVED_IDX;
		}

		if(subEmitters != null) {
			for( s in subEmitters )
				s.remove();
			subEmitters = null;
		}

		if (trails != null) {
			trails.reset();
		}
	}

	inline function checkList() { /*
		var p = listHead;
		var tail = null;
		var count = 0;
		while(p != null) {
			++count;
			if(p.idx == ParticleInstance.REMOVED_IDX)
				throw "!";
			var n = p.next;
			if(n != null)
				if(n.prev != p) throw "!";
			if(p.next != null)
				p = p.next;
			else {
				tail = p;
				break;
			}
		}
		if(count != numInstances) throw count + "!=" + numInstances;
		p = tail;
		count = 0;
		while(p != null) {
			++count;
			p = p.prev;
		}
		if(count != numInstances) throw count + "!=" + numInstances;
		#end */
	}

	function allocInstance() {
		if(numInstances >= maxCount) throw "assert";
		var p = particles[numInstances++];
		p.init(instanceCounter, this);
		p.prev = null;
		p.next = listHead;
		if(listHead != null)
			listHead.prev = p;
		listHead = p;
		instanceCounter = (instanceCounter + 1) % maxCount;
		checkList();
		return p;
	}

	function disposeInstance(idx: Int) {
		checkList();
		--numInstances;
		if(numInstances < 0)
			throw "assert";

		// stitch list after remove
		var o = particles[idx];

		if(o.idx == ParticleInstance.REMOVED_IDX) throw "!";
		var prev = o.prev;
		var next = o.next;
		if(prev != null) {
			if(prev.next == next) throw "!";
			prev.next = next;
		}
		else {
			if(listHead != o) throw "!";
			if(listHead == next) throw "!";
			listHead = next;
		}
		if(next != null) {
			if(next.prev == prev) throw "!";
			next.prev = prev;
		}

		// remove swap
		if(idx < numInstances) {
			var swap = particles[numInstances];
			o.load(swap);
			swap.idx = ParticleInstance.REMOVED_IDX;
			if(swap.prev != null)
				swap.prev.next = o;
			if(swap.next != null)
				swap.next.prev = o;
			if(listHead == swap)
				listHead = o;
		}
		else
			o.idx = ParticleInstance.REMOVED_IDX;

		checkList();
		return idx;
	}

	var tmpCtx : hrt.prefab.Context;
	static var tmpQuat = new h3d.Quat();
	static var tmpEmitterQuat = new h3d.Quat();
	static var tmpOffset = new h3d.Vector();
	static var tmpVec = new h3d.Vector();
	static var tmpVec2 = new h3d.Vector();
	static var tmpDir = new h3d.Vector();
	static var tmpScale = new h3d.Vector();
	static var tmpMat = new h3d.Matrix();
	static var tmpMat2 = new h3d.Matrix();
	static var tmpPt = new h3d.col.Point();
	function doEmit( count : Int ) {
		if( count == 0 )
			return;

		if( instDef == null)
			return;

		var emitterQuat : h3d.Quat = null;
		if (count > 0) {

			if (trailsTemplate != null && trails == null) {
				if( tmpCtx == null ) {
					tmpCtx = new hrt.prefab.Context();
					tmpCtx.shared = context.shared;
				}
				tmpCtx.custom = {numTrails: maxCount};
				tmpCtx.local3d = this;
				trails = cast trailsTemplate.make(tmpCtx).local3d;
				trails.autoTrackPosition = false;
			}

			for( i in 0...count ) {
				var part = allocInstance();
				part.startTime = startTime + curTime;
				part.lifeTime = hxd.Math.max(0.01, lifeTime + random.srand(lifeTimeRand));

				if(useRandomColor) {
					if (useRandomGradient) {
						part.colorMult = Gradient.evalData(randomGradient, random.rand()).toColor();
					}
					else {
						var col = new h3d.Vector();
						col.lerp(randomColor1, randomColor2, random.rand());
						part.colorMult = col.toColor();
					}
				}

				tmpQuat.identity();

				switch( emitShape ) {
					case Box:
						tmpOffset.set(random.srand(0.5), random.srand(0.5), random.srand(0.5));
						if( emitSurface ) {
							var max = Math.max(Math.max(Math.abs(tmpOffset.x), Math.abs(tmpOffset.y)), Math.abs(tmpOffset.z));
							tmpOffset.scale(0.5 / max);
						}
						if( emitOrientation == Normal )
							tmpQuat.initDirection(tmpOffset);
					case Cylinder:
						var z = random.rand();
						var dx = 0.0, dy = 0.0;
						var shapeAngle = hxd.Math.degToRad(emitAngle) / 2.0;
						var a = random.srand(shapeAngle);
						if(emitSurface) {
							dx = Math.cos(a)*(emitRad2*z + emitRad1*(1.0-z));
							dy = Math.sin(a)*(emitRad2*z + emitRad1*(1.0-z));
						}
						else {
							dx = Math.cos(a)*(emitRad2*z + emitRad1*(1.0-z))*random.rand();
							dy = Math.sin(a)*(emitRad2*z + emitRad1*(1.0-z))*random.rand();
						}
						tmpOffset.set(dx * 0.5, dy * 0.5, z - 0.5);
						if( emitOrientation == Normal )
							tmpQuat.initRotation(0, 0, hxd.Math.atan2(dy, dx));
					case Sphere:
						do {
							tmpOffset.x = random.srand(1.0);
							tmpOffset.y = random.srand(1.0);
							tmpOffset.z = random.srand(1.0);
						}
						while( tmpOffset.lengthSq() > 1.0 );
						if( emitSurface )
							tmpOffset.normalize();
						tmpOffset.scale3(0.5);
						if( emitOrientation == Normal )
							tmpQuat.initDirection(tmpOffset);
					case Cone:
						tmpOffset.set(0, 0, 0);
						var theta = random.rand() * Math.PI * 2;
						var shapeAngle = hxd.Math.degToRad(emitAngle) / 2.0;
						var phi = shapeAngle * random.rand();
						tmpDir.x = Math.cos(phi) * scaleX;
						tmpDir.y = Math.sin(phi) * Math.sin(theta) * scaleY;
						tmpDir.z = Math.sin(phi) * Math.cos(theta) * scaleZ;
						tmpDir.normalizeFast();
						tmpQuat.initDirection(tmpDir);
				}

				if( emitOrientation == Random )
					tmpQuat.initRotation(hxd.Math.srand(Math.PI), hxd.Math.srand(Math.PI), hxd.Math.srand(Math.PI));

				switch( simulationSpace ) {
					case Local:
						if(emitterQuat == null) {
							emitterQuat = tmpEmitterQuat;
							emitterQuat.load(getRotationQuat());
							tmpMat.load(getAbsPos());
							tmpMat2.load(parent.getAbsPos());
							tmpMat2.invert();
							tmpMat.multiply(tmpMat, tmpMat2);
						}

						tmpOffset.transform(tmpMat);
						part.setPosition(tmpOffset.x, tmpOffset.y, tmpOffset.z);
						tmpQuat.multiply(emitterQuat, tmpQuat);
						part.qRot.loadQuat(tmpQuat);
						tmpQuat.toMatrix(tmpMat2);
						part.emitOrientation.load(tmpMat2);
					case World:
						tmpPt.set(tmpOffset.x, tmpOffset.y, tmpOffset.z);
						localToGlobal(tmpPt);
						part.setPosition(tmpPt.x, tmpPt.y, tmpPt.z);
						emitterQuat = tmpEmitterQuat;
						tmpMat.load(getAbsPos());
						var s = tmpMat.getScale();
						tmpMat.prependScale(1.0/s.x, 1.0/s.y, 1.0/s.z);
						emitterQuat.initRotateMatrix(tmpMat);
						emitterQuat.normalize();
						tmpQuat.multiply(tmpQuat, emitterQuat);
						part.qRot.loadQuat(tmpQuat);
						tmpQuat.toMatrix(tmpMat2);
						part.emitOrientation.load(tmpMat2);
						part.setScale(worldScale.x, worldScale.y, worldScale.z);
				}
				var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
				if(animationLoop)
					part.startFrame = random.random(frameCount);

			}
		}

		context.local3d = this;
		emitCount += count;
	}

	// No-alloc version of h3d.Matrix.getEulerAngles()
	static function getEulerAngles(m: h3d.Matrix) {
		var s = m.getScale();
		m.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
		var cy = hxd.Math.sqrt(m._11 * m._11 + m._12 * m._12);
		if(cy > 0.01) {
			tmpVec.set(
				hxd.Math.atan2(m._23, m._33),
				hxd.Math.atan2(-m._13, cy),
				hxd.Math.atan2(m._12, m._11));

			tmpVec2.set(
				hxd.Math.atan2(-m._23, -m._33),
				hxd.Math.atan2(-m._13, -cy),
				hxd.Math.atan2(-m._12, -m._11));

			return tmpVec.lengthSq() < tmpVec2.lengthSq() ? tmpVec : tmpVec2;
		}
		else {
			tmpVec.set(
				hxd.Math.atan2(-m._32, m._22),
				hxd.Math.atan2(-m._13, cy),
				0.0);
			return tmpVec;
		}
	}

	function tick( dt : Float, full=true) {

		// Auto remove of sub emitters
		if( !enable && particles == null && isSubEmitter ) {
			parentEmitter.subEmitters.remove(this);
			remove();
			return;
		}

		if(subEmitters != null) {
			for( se in subEmitters ) {
				se.tick(dt);
			}
		}

		if( emitRate == null || emitRate == VZero )
			return;

		if( parent != null ) {
			worldScale.load(parent.getAbsPos().getScale());
			invTransform.load(parent.getInvPos());
		}

		if( enable ) {
			switch emitType {
				case Infinity:
					emitTarget += evaluator.getFloat(emitRate, curTime) * dt;
					var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, emitTarget - emitCount));
					doEmit(delta);
					if( isSubEmitter && (parentEmitter == null || parentEmitter.parent == null) )
						enable = false;
				case InfinityRandom:
					var min = evaluator.getFloat(emitRateMin, curTime);
					var max = evaluator.getFloat(emitRateMax, curTime);

					if (emitRateCurrent == null) {
						emitRateCurrent = random.rand() * (max-min) + min;
						emitRateLastChangeTime = emitRateChangeDelay;
					}

					if (emitRateLastChangeTime >= emitRateChangeDelay) {
						emitRateLastChangeTime = emitRateLastChangeTime % emitRateChangeDelay;
						var target = random.rand() * (max-min) + min;
						emitRateChange = (target-emitRateCurrent) / (emitRateChangeDelay - emitRateLastChangeTime);
					}

					emitRateCurrent += emitRateChange * dt;
					emitRateLastChangeTime += dt;

					emitTarget += emitRateCurrent * dt;
					var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, emitTarget - emitCount));
					doEmit(delta);
					if( isSubEmitter && (parentEmitter == null || parentEmitter.parent == null) )
						enable = false;
				case Duration:
					emitTarget += evaluator.getFloat(emitRate, hxd.Math.min(curTime, emitDuration)) * dt;
					var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, emitTarget - emitCount));
					doEmit(delta);
					if( isSubEmitter && curTime >= emitDuration )
						enable = false;
				case BurstDuration:
					if( burstDelay > 0 ) {
						var burstTarget = 1 + hxd.Math.floor(curTime / burstDelay);
						var lastBurstTime = totalBurstCount * burstDelay;
						var nextBurstTime = lastBurstTime + burstDelay;
						var needBurst = nextBurstTime <= emitDuration && totalBurstCount < burstTarget;
						while( needBurst ) {
							var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, burstParticleCount));
							doEmit(delta);
							totalBurstCount++;
							lastBurstTime += burstDelay;
							nextBurstTime = lastBurstTime + burstDelay;
							needBurst = nextBurstTime <= emitDuration && totalBurstCount < burstTarget;
						}
					}
					if( isSubEmitter && curTime > emitDuration )
						enable = false;
				case Burst:
					if( burstDelay > 0 ) {
						var burstTarget = hxd.Math.min(burstCount, 1 + hxd.Math.floor(curTime / burstDelay));
						while( totalBurstCount < burstTarget ) {
							var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, burstParticleCount));
							doEmit(delta);
							totalBurstCount++;
						}
					}
					if( isSubEmitter && totalBurstCount == burstCount )
						enable = false;

			}
		}

		if( full )
			updateAlignment();

		updateParticles(full, dt);

		if( full )
			updateMeshBatch();

		curTime += dt;
	}

	function updateAlignment() {
		if(alignMode == Screen) {
			tmpMat.load(getScene().camera.mcam);
			tmpMat.invert();

			if(simulationSpace == Local) {  // Compensate parent rotation
				tmpMat2.load(parent.getAbsPos());
				var s = tmpMat2.getScale();
				tmpMat2.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
				tmpMat2.invert();
				tmpMat.multiply(tmpMat, tmpMat2);
			}

			screenQuat.initRotateMatrix(tmpMat);
			tmpQuat.initRotateAxis(1,0,0,Math.PI);  // Flip Y axis so Y is pointing down
			screenQuat.multiply(screenQuat, tmpQuat);
		}
		else if(alignMode == Axis) {
			var lockAxis = new h3d.Vector();
			var frontAxis = new h3d.Vector(1, 0, 0);
			switch alignLockAxis {
				case X: lockAxis.set(1, 0, 0);
				case Y: lockAxis.set(0, 1, 0);
				case Z: lockAxis.set(0, 0, 1);
				case ScreenZ:
					lockAxis.set(0, 0, 1);
					frontAxis.set(0, 1, 0);
			}

			var lookAtPos = tmpVec;
			lookAtPos.load(getScene().camera.pos);
			var invParent = parent.getInvPos();
			lookAtPos.transform(invTransform);
			var deltaVec = new h3d.Vector(lookAtPos.x - x, lookAtPos.y - y, lookAtPos.z - z);

			var invParentQ = tmpQuat;
			invParentQ.initRotateMatrix(invParent);

			var targetOnPlane = h3d.col.Plane.fromNormalPoint(lockAxis.toPoint(), new h3d.col.Point()).project(deltaVec.toPoint()).toVector();
			targetOnPlane.normalize();
			var angle = hxd.Math.acos(frontAxis.dot(targetOnPlane));

			var cross = frontAxis.cross(deltaVec);
			if(lockAxis.dot(cross) < 0)
				angle = -angle;

			screenQuat.initRotateAxis(lockAxis.x, lockAxis.y, lockAxis.z, angle);
			screenQuat.normalize();
			if(alignLockAxis == ScreenZ) {
				tmpQuat.initRotateAxis(1,0,0,-Math.PI/2);
				screenQuat.multiply(screenQuat, tmpQuat);
			}
		}
	}

	static function sortZ( p1 : ParticleInstance, p2 : ParticleInstance ) : Int {
		return p1.distToCam < p2.distToCam ? 1 : -1;
	}

	function depthSort() {
		checkList();
		listHead = haxe.ds.ListSort.sort(listHead, sortZ);
		if(listHead != null)
			listHead.prev = null;  // The `prev` of the head is set to the tail of the sorted list.
		checkList();
	}

	function updateMeshBatch() {
		if(batch == null) return;
		batch.begin(hxd.Math.nextPOT(maxCount));

		inline function emit(p: ParticleInstance) {
			if (p.life > p.lifeTime)
				return;
			inline tmpMat.load(p.absPos.toMatrix());
			batch.worldPosition = tmpMat;
			for( anim in shaderAnims ) {
				var t = hxd.Math.clamp(p.life / p.lifeTime, 0.0, 1.0);
				anim.setTime(t);
			}
			if( animatedTextureShader != null ){
				animatedTextureShader.startTime = p.startTime;
				animatedTextureShader.startFrame = p.startFrame;
			}

			baseEmitterShader.life = p.life;
			baseEmitterShader.lifeTime = p.lifeTime;
			baseEmitterShader.random = p.random;

			if(colorMultShader != null)
				colorMultShader.color.setColor(p.colorMult);
			batch.emitInstance();
		}

		if(enableSort) {
			depthSort();
			var p = listHead;
			while(p != null) {
				emit(p);
				p = p.next;
			}
		}
		else {
			for(i in 0...numInstances)
				emit(particles[i]);
		}
	}

	function updateParticles(full: Bool, dt: Float) {

		switch(simulationSpace){
			// Particles in Local are spawned next to emitter in the scene tree,
			// so emitter shape can be transformed (especially scaled) without affecting children
			case Local : parentTransform.load(parent.getAbsPos());
			case World : parentTransform.load(getScene().getAbsPos());
			// Optim: set to null if identity to skip multiply in particle updates
		}

		var prev : ParticleInstance = null;
		var camPos = getScene().camera.pos;

		if (trails != null) {
			trails.numTrails = maxCount;
		}

		var i = 0;
		while(i < numInstances) {
			var p = particles[i];
			if(p.life > p.lifeTime) {
				if (p.trail == null || p.trail.generation != p.trailGeneration) {
					i = disposeInstance(i);
					// SUB EMITTER
					if( subEmitterTemplates != null ) {
						if( tmpCtx == null ) {
							tmpCtx = new hrt.prefab.Context();
							tmpCtx.local3d = this.getScene();
							tmpCtx.shared = context.shared;
						}
						tmpCtx.local3d = this.getScene();
						for (sub in subEmitterTemplates) {
							var emitter : EmitterObject = cast sub.makeInstance(tmpCtx).local3d;
							var pos = p.absPos.getPosition();
							emitter.setPosition(pos.x, pos.y, pos.z);
							emitter.isSubEmitter = true;
							emitter.parentEmitter = this;
							if(subEmitters == null)
								subEmitters = [];
							subEmitters.push(emitter);
						}
					}
				} else {
					prev = p;
					++i;
				}
			}
			else {
				p.update(this, dt);
				if(full) {
					p.updateAbsPos(this);
					if(p.distToCam < 0 || enableSort)
						p.distToCam = camPos.distanceSq(p.absPos.getPosition());
				}
				p.life += dt;  // After updateAbsPos(), which uses current life
				prev = p;
				++i;

				if (trails != null) {
					trails.addPoint(p.trail, p.absPos._41, p.absPos._42, p.absPos._43, ECamera, 1.0);
				}
			}
		}
	}

	public function setRandSeed(seed: Int) {
		randomSeed = seed ^ seedGroup;
		reset();
	}

	#if editor
	public var tickTime : Float = 0;
	#end

	public function setTime(time: Float) {
		time = time * speedFactor + warmUpTime;
		if(hxd.Math.abs(time - curTime) < 1e-6) {  // Time imprecisions can occur during accumulation
			updateAlignment();
			for(i in 0...numInstances)
				particles[i].updateAbsPos(this);
			updateMeshBatch();
			return;
		}

		if(time < curTime) {
			reset();
			updateMeshBatch();  // Make sure mesh batch is reset even when no tick is called()
		}

		var catchupTime = time - curTime;

		#if !editor  // Limit catchup time to avoid spikes when showing long running FX
		var longCatchup = catchupTime > maxCatchupWindow;
		if(longCatchup) {
			var firstWarmup = curTime <= 0.0 && warmUpTime > 0;
			catchupTime = firstWarmup ? warmUpTime : maxCatchupWindow;
			curTime = time - catchupTime;
			emitCount = hxd.Math.ceil(evaluator.getSum(emitRate, curTime));

			// Force sort after long time invisible
			for(i in 0...numInstances)
				particles[i].distToCam = -1;
		}
		#end

		var catchupTickRate = hxd.Timer.wantedFPS * speedFactor / catchupSpeed;
		var numTicks = hxd.Math.ceil(catchupTickRate * catchupTime);
		for(i in 0...numTicks)
		{
			#if editor
			var start = haxe.Timer.stamp();
			#end
			tick(catchupTime / numTicks, i == (numTicks - 1));
			#if editor
			var end = haxe.Timer.stamp();
			tickTime = end - start;
			#end
		}
	}

	override function getBoundsRec( b : h3d.col.Bounds ) {
		if( posChanged ) {
			posChanged = false;
			calcAbsPos();
		}
		return b;
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
		// PROPERTIES
		{ name: "lifeTime", t: PFloat(0, 10), def: 1.0, groupName : "Properties" },
		{ name: "lifeTimeRand", t: PFloat(0, 1), def: 0.0, groupName : "Properties" },
		{ name: "speedFactor", disp: "Speed Factor", t: PFloat(0, 1), def: 1.0, groupName : "Properties" },
		{ name: "warmUpTime", disp: "Warm Up", t: PFloat(0, 1), def: 0.0, groupName : "Properties" },
		{ name: "seedGroup", t: PInt(0, 100), def: 0, groupName : "Properties", disp: "Seed"},
		{ name: "alignMode", t: PEnum(AlignMode), def: AlignMode.None, disp: "Mode", groupName : "Properties" },
		{ name: "alignLockAxis", t: PEnum(AlignLockAxis), def: AlignLockAxis.ScreenZ, disp: "Lock Axis", groupName : "Properties" },
		{ name: "simulationSpace", t: PEnum(SimulationSpace), def: SimulationSpace.Local, disp: "Simulation Space", groupName : "Properties" },
		{ name: "enableSort", t: PBool, def: true, disp: "Enable Sort", groupName : "Properties"},

		// EMIT PARAMS
		{ name: "emitType", t: PEnum(EmitType), def: EmitType.Infinity, disp: "Type", groupName : "Emit Params"  },
		{ name: "emitDuration", t: PFloat(0, 10.0), disp: "Duration", def : 1.0, groupName : "Emit Params" },
		{ name: "emitRate", t: PInt(0, 100), def: 5, disp: "Rate", animate: true, groupName : "Emit Params" },
		{ name: "emitRateMin", t: PInt(0, 100), def: 5, disp: "Rate Min", animate: true, groupName : "Emit Params" },
		{ name: "emitRateMax", t: PInt(0, 100), def: 5, disp: "Rate Max", animate: true, groupName : "Emit Params" },
		{ name: "emitRateChangeDelay", t: PFloat(0.01, 5.0), def: 1.0, disp: "Rate Change Time", groupName : "Emit Params" },
		{ name: "burstCount", t: PInt(1, 10), disp: "Count", def : 1, groupName : "Emit Params" },
		{ name: "burstDelay", t: PFloat(0, 1.0), disp: "Delay", def : 1.0, groupName : "Emit Params" },
		{ name: "burstParticleCount", t: PInt(1, 10), disp: "Particle Count", def : 1, groupName : "Emit Params" },
		{ name: "maxCount", t: PInt(0, 100), def: 20, groupName : "Emit Params" },
		// EMIT SHAPE
		{ name: "emitShape", t: PEnum(EmitShape), def: EmitShape.Sphere, disp: "Shape", groupName : "Emit Shape" },
		{ name: "emitAngle", t: PFloat(0, 360.0), def: 30.0, disp: "Angle", groupName : "Emit Shape" },
		{ name: "emitRad1", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 1", groupName : "Emit Shape" },
		{ name: "emitRad2", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 2", groupName : "Emit Shape" },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface", groupName : "Emit Shape" },
		{ name: "emitOrientation", t: PEnum(Orientation), def: Orientation.Forward, disp: "Orientation", groupName : "Emit Params" },
		// COLOR
		{ name: "useRandomColor", t: PBool, def: false, disp: "Random Color", groupName : "Color" },
		{ name: "useRandomGradient", t: PBool, def: false, disp: "Random Gradient", groupName : "Color" },
		{ name: "randomColor1", t: PVec(4), disp: "Color 1", def : [0,0,0,1], groupName : "Color" },
		{ name: "randomColor2", t: PVec(4), disp: "Color 2", def : [1,1,1,1], groupName : "Color" },
		{ name: "randomGradient", t:PGradient, disp: "Gradient", def: Gradient.getDefaultGradientData(), groupName : "Color" },
		// ANIMATION
		{ name: "spriteSheet", t: PFile(["jpg","png"]), def: null, groupName : "Sprite Sheet Animation", disp: "Sheet" },
		{ name: "frameCount", t: PInt(0), def: 0, groupName : "Sprite Sheet Animation", disp: "Frames" },
		{ name: "frameDivisionX", t: PInt(1), def: 1, groupName : "Sprite Sheet Animation", disp: "Divisions X" },
		{ name: "frameDivisionY", t: PInt(1), def: 1, groupName : "Sprite Sheet Animation", disp: "Divisions Y" },
		{ name: "animationSpeed", t: PFloat(0, 2.0), def: 1.0, groupName : "Sprite Sheet Animation", disp: "Speed" },
		{ name: "animationLoop", t: PBool, def: true, groupName : "Sprite Sheet Animation", disp: "Loop" },
		// COLLISION
		{ name: "useCollision", t: PBool, def: false, groupName : "Ground Collision" },
		{ name: "elasticity", t: PFloat(0, 1.0), disp: "Elasticity", def : 1.0, groupName : "Ground Collision" },
		{ name: "killOnCollision", t: PFloat(0, 1.0), disp: "Kill On Collision", def : 0.0, groupName : "Ground Collision" },
	];

	public static var instanceParams : Array<ParamDef> = [
		{ name: "instWorldAcceleration",	t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "World Acceleration", groupName: "Particle Movement"},
		{ name: "instSpeed",      			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Fixed Speed", groupName: "Particle Movement" },
		{ name: "instWorldSpeed", 			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Fixed World Speed", groupName: "Particle Movement"},
		{ name: "instStartSpeed",      		t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Start Speed",groupName: "Particle Movement"},
		{ name: "instStartWorldSpeed", 		t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Start World Speed",groupName: "Particle Movement"},
		{ name: "instOrbitSpeed", 			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Orbit Speed", groupName: "Particle Movement"},
		{ name: "instAcceleration",			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Acceleration", groupName: "Particle Movement"},
		{ name: "instMaxVelocity",      			t: PFloat(0, 10.0),    def: 0.,         disp: "Max Velocity", groupName: "Limit Velocity"},
		{ name: "instDampen",      			t: PFloat(0, 10.0),    def: 0.,         disp: "Dampen", groupName: "Limit Velocity"},
		{ name: "instScale",      			t: PFloat(0, 2.0),    def: 1.,         disp: "Scale", groupName: "Particle Transform"},
		{ name: "instStretch",    			t: PVec(3, 0.0, 2.0), def: [1.,1.,1.], disp: "Stretch", groupName: "Particle Transform"},
		{ name: "instStretchVelocity",    	t: PFloat(0.0, 2.0), def: 0.0, disp: "Stretch Vel.", groupName: "Particle Transform"},
		{ name: "instRotation",   			t: PVec(3, 0, 360),   def: [0.,0.,0.], disp: "Rotation", groupName: "Particle Transform"},
		{ name: "instOffset",     			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Offset", groupName: "Particle Transform"},
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

	override function make(ctx: Context) {
		if( ctx == null ) {
			ctx = new Context();
			ctx.init();
		}
		ctx = makeInstance(ctx);
		return ctx;
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
		var a = Std.downcast(param.def, Array);
		if(a != null)
			Reflect.setField(props, param.name, a.copy());
		else
			Reflect.setField(props, param.name, param.def);
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var emitterObj = Std.downcast(ctx.local3d, EmitterObject);

		var randIdx = 0;
		var template : Object3D = cast children.find( 
			c -> c.enabled &&
			(c.name == null || c.name.indexOf("collision") == -1) &&
			c.to(Object3D) != null &&
			c.to(Object3D).visible &&
			c.to(Emitter) == null &&
			c.to(hrt.prefab.l3d.Trails) == null);

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
						switch b {
							case VConst(vb): return VConst(va * vb);
							case VCurve(cb): return VCurveScale(cb, va);
							default:
						}
					case VCurve(ca):
						switch b {
							case VConst(vb): return VCurveScale(ca, vb);
							default:
						}
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
				throw "Need optimization" + Std.string(a)+ " * " + Std.string(b);
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
				var randCurve = getCurve(pname + suffix + ".rand");
				var randVal : Value = VZero;
				if(randCurve != null)
					randVal = VRandom(randIdx++, VCurveScale(randCurve, randProp != null ? randProp : 1.0));
				else if(randProp != null && randProp != 0.0)
					randVal = VRandomScale(randIdx++, randProp);

				var xCurve = getCurve(pname + suffix);
				if (xCurve != null)
					if (pname.indexOf("Rotation") >= 0 || pname.indexOf("Offset") >= 0)
						return vAdd(vAdd(xVal, randVal), VCurve(xCurve));
					else
						return vMult(vAdd(xVal, randVal), VCurve(xCurve));
				else
					return vAdd(xVal, randVal);
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
					var v : Value = VVector(
						makeComp(0, ".x"),
						makeComp(1, ".y"),
						makeComp(2, ".z"));
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
		d.startSpeed = makeParam(this, "instStartSpeed");
		d.startWorldSpeed = makeParam(this, "instStartWorldSpeed");
		d.orbitSpeed = makeParam(this, "instOrbitSpeed");
		d.acceleration = makeParam(this, "instAcceleration");
		d.worldAcceleration = makeParam(this, "instWorldAcceleration");
		d.localOffset = makeParam(this, "instOffset");
		d.scale = makeParam(this, "instScale");
		d.dampen = makeParam(this, "instDampen");
		d.maxVelocity = makeParam(this, "instMaxVelocity");
		d.stretch = makeParam(this, "instStretch");
		d.stretchVelocity = makeParam(this, "instStretchVelocity");
		d.rotation = makeParam(this, "instRotation");
		emitterObj.instDef = d;
		emitterObj.particleTemplate = template;

		// SUB-EMITTER
		var subEmitterTemplates : Array<Prefab> = children.filter( p -> p.enabled && Std.downcast(p, Emitter) != null && p.to(Object3D).visible);
		emitterObj.subEmitterTemplates = subEmitterTemplates.length > 0 ? [for (s in subEmitterTemplates) cast s] : null;

		// TRAILS
		var trailsTemplate : hrt.prefab.l3d.Trails = cast children.find(p -> p.enabled && Std.isOfType(p, hrt.prefab.l3d.Trails) && p.to(Object3D).visible);
		emitterObj.trailsTemplate = trailsTemplate;

		// RANDOM
		emitterObj.seedGroup 			= 	getParamVal("seedGroup");
		// LIFE
		emitterObj.lifeTime 			= 	getParamVal("lifeTime");
		emitterObj.lifeTimeRand 		= 	getParamVal("lifeTimeRand");
		emitterObj.speedFactor 			= 	getParamVal("speedFactor");
		emitterObj.warmUpTime 			= 	getParamVal("warmUpTime");
		// EMIT PARAMS
		emitterObj.emitType 			= 	getParamVal("emitType");
		emitterObj.burstCount 			= 	getParamVal("burstCount");
		emitterObj.burstDelay 			= 	getParamVal("burstDelay");
		emitterObj.burstParticleCount 	= 	getParamVal("burstParticleCount");
		emitterObj.emitDuration 		= 	getParamVal("emitDuration");
		emitterObj.simulationSpace 		= 	getParamVal("simulationSpace");
		emitterObj.emitOrientation 		= 	getParamVal("emitOrientation");
		emitterObj.maxCount 			= 	getParamVal("maxCount");
		emitterObj.enableSort 			= 	getParamVal("enableSort");
		emitterObj.emitRate 			= 	makeParam(this, "emitRate");
		emitterObj.emitRateMin 			= 	makeParam(this, "emitRateMin");
		emitterObj.emitRateMax 			= 	makeParam(this, "emitRateMax");
		emitterObj.emitRateChangeDelay 	= 	getParamVal("emitRateChangeDelay");
		emitterObj.emitShape 			= 	getParamVal("emitShape");
		// EMIT SHAPE
		emitterObj.emitAngle 			= 	getParamVal("emitAngle");
		emitterObj.emitRad1 			= 	getParamVal("emitRad1");
		emitterObj.emitRad2 			= 	getParamVal("emitRad2");
		emitterObj.emitSurface 			= 	getParamVal("emitSurface");
		// ALIGNMENT
		emitterObj.alignMode 			= 	getParamVal("alignMode");
		emitterObj.alignLockAxis 		= 	getParamVal("alignLockAxis");
		// ANIMATION
		emitterObj.spriteSheet 			= 	getParamVal("spriteSheet");
		emitterObj.frameCount 			= 	getParamVal("frameCount");
		emitterObj.frameDivisionX 		= 	getParamVal("frameDivisionX");
		emitterObj.frameDivisionY 		= 	getParamVal("frameDivisionY");
		emitterObj.animationSpeed 		= 	getParamVal("animationSpeed");
		emitterObj.animationLoop 		= 	getParamVal("animationLoop");
		// COLLISION
		emitterObj.useCollision 		= 	getParamVal("useCollision");
		emitterObj.killOnCollision 		= 	getParamVal("killOnCollision");
		emitterObj.elasticity 			= 	getParamVal("elasticity");
		// RANDOM COLOR
		emitterObj.useRandomColor 		= 	getParamVal("useRandomColor");
		emitterObj.useRandomGradient 	= 	getParamVal("useRandomGradient");
		emitterObj.randomColor1 		= 	getParamVal("randomColor1");
		emitterObj.randomColor2 		= 	getParamVal("randomColor2");
		emitterObj.randomGradient 		= 	getParamVal("randomGradient");



		#if !editor  // Keep startTime at 0 in Editor, since global.time is synchronized to timeline
		var scene = ctx.local3d.getScene();
		if(scene != null)
			emitterObj.startTime = @:privateAccess scene.renderer.ctx.time;
		#end

		emitterObj.init(randIdx, this);

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

		function onChange(?pname: String) {
			ctx.onChange(this, pname);

			if(["emitShape",
				"alignMode",
				"useCollision",
				"emitType",
				"useRandomColor",
				"useRandomGradient"].indexOf(pname) >= 0)
				refresh();
		}

		var params = emitterParams.copy();
		inline function removeParam(pname: String) {
			params.remove(params.find(p -> p.name == pname));
		}

		var emitShape : EmitShape = getParamVal("emitShape");
		if(!(emitShape == Cone || emitShape == Cylinder))
			removeParam("emitAngle");
		if(emitShape != Cylinder) {
			removeParam("emitRad1");
			removeParam("emitRad2");
		}

		var alignMode : AlignMode = getParamVal("alignMode");
		switch(alignMode) {
			case None | Screen:
				removeParam("alignLockAxis");
			default:
		}

		var useCollision = getParamVal("useCollision");
		if( !useCollision ) {
			removeParam("elasticity");
			removeParam("killOnCollision");
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
				var group = new Element('<div class="group" name="$gn"></div>');
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
				var instGroup = new Element('<div class="group" name="$groupName"></div>');
				var dl = new Element('<dl>').appendTo(instGroup);

				for (p in params) {
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

				ctx.properties.add(instGroup, this.props, onChange);
			}
		}
	}

	override function setSelected( ctx : Context, b : Bool ) {
		var emitterObj = Std.downcast(ctx.local3d, EmitterObject);
		if(emitterObj == null)
			return false;
		var debugShape : h3d.scene.Object = emitterObj.find(c -> if(c.name == "_highlight") c else null);
		if(debugShape != null)
			debugShape.visible = b;

		if( false && emitterObj.batch != null ) {  // Disabling, selection causes crashes
			if( b ) {
				var shader = new h3d.shader.FixedColor(0xffffff);
				var p = emitterObj.batch.material.allocPass("highlight");
				p.culling = None;
				p.depthWrite = false;
				p.addShader(shader);
				@:privateAccess p.batchMode = true;
			}
			else {
				emitterObj.batch.material.removePass(emitterObj.batch.material.getPass("highlight"));
			}
			emitterObj.batch.shadersChanged = true;
		}
		return false;
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

		var mesh : h3d.scene.Mesh = null;
		switch(emitterObj.emitShape) {
			case Cylinder: {
				var rad1 = getParamVal("emitRad1") * 0.5;
				var rad2 = getParamVal("emitRad2") * 0.5;
				var angle = hxd.Math.degToRad(getParamVal("emitAngle"));

				inline function circle(npts, f) {
					for(i in 0...(npts+1)) {
						var t = Math.PI + (i / npts) * angle + (Math.PI*2 - angle) * 0.5;
						var c = hxd.Math.cos(t);
						var s = hxd.Math.sin(t);
						f(i, c, s);
					}
				}

				var g = new h3d.scene.Graphics(debugShape);
				g.material.mainPass.setPassName("overlay");
				g.lineStyle(1, 0xffffff);
				circle(32, function(i, c, s) {
					if(i == 0)
						g.moveTo(c * rad1, s * rad1, -0.5);
					else
						g.lineTo(c * rad1, s * rad1, -0.5);
				});
				circle(32, function(i, c, s) {
					if(i == 0)
						g.moveTo(c * rad2, s * rad2, 0.5);
					else
						g.lineTo(c * rad2, s * rad2, 0.5);
				});
				g.lineStyle(1, 0xffffff);
				circle(8, function(i, c, s) {
					g.moveTo(c * rad1, s * rad1, -0.5);
					g.lineTo(c * rad2, s * rad2, 0.5);
				});
				g.ignoreCollide = true;
				mesh = g;
			}
			case Box: {
				mesh = new h3d.scene.Box(0xffffff, true, debugShape);
			}
			case Cone: {
				inline function circle(npts, f) {
					for(i in 0...(npts+1)) {
						var t = (i / npts) * hxd.Math.PI * 2.0;
						var c = hxd.Math.cos(t);
						var s = hxd.Math.sin(t);
						f(i, c, s);
					}
				}

				var g = new h3d.scene.Graphics(debugShape);
				g.material.mainPass.setPassName("overlay");
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

	static var _ = Library.register("emitter", Emitter);

}

@:publicFields @:struct
class SVector3 {
	var x : Single;
	var y : Single;
	var z : Single;
	public function new() { }

	inline function toVector() {
		return new h3d.Vector(x, y, z);
	}
	inline function load(v: h3d.Vector) {
		this.x = v.x;
		this.y = v.y;
		this.z = v.z;
	}
}

@:publicFields @:struct
class SVector4 {
	var x : Single;
	var y : Single;
	var z : Single;
	var w : Single;

	public function new() { }


	inline function toQuat() {
		return new h3d.Quat(x, y, z, w);
	}

	inline function load(v: h3d.Vector) {
		this.x = v.x;
		this.y = v.y;
		this.z = v.z;
		this.w = v.w;
	}

	inline function loadQuat(q: h3d.Quat) {
		this.x = q.x;
		this.y = q.y;
		this.z = q.z;
		this.w = q.w;
	}

	inline function toVector() {
		return new h3d.Vector(x, y, z, w);
	}
}


@:publicFields @:struct
class SMatrix3 {
	var _11 : Single; var _12 : Single; var _13 : Single;
	var _21 : Single; var _22 : Single; var _23 : Single;
	var _31 : Single; var _32 : Single; var _33 : Single;

	public function new() { }

	inline function toMatrix() {
		var m = new h3d.Matrix();
		m._11 = _11; m._12 = _12; m._13 = _13;
		m._21 = _21; m._22 = _22; m._23 = _23;
		m._31 = _31; m._32 = _32; m._33 = _33;
		return m;
	}

	inline function load(m : h3d.Matrix) {
		_11 = m._11; _12 = m._12; _13 = m._13;
		_21 = m._21; _22 = m._22; _23 = m._23;
		_31 = m._31; _32 = m._32; _33 = m._33;
	}
}


@:publicFields @:struct
class SMatrix4 {
	var _11 : Single; var _12 : Single; var _13 : Single; var _14 : Single;
	var _21 : Single; var _22 : Single; var _23 : Single; var _24 : Single;
	var _31 : Single; var _32 : Single; var _33 : Single; var _34 : Single;
	var _41 : Single; var _42 : Single; var _43 : Single; var _44 : Single;

	public function new() { }

	public inline function getPosition() {
		var v = new h3d.Vector();
		v.set(_41,_42,_43,_44);
		return v;
	}

	inline function toMatrix() {
		var m = new h3d.Matrix();
		m._11 = _11; m._12 = _12; m._13 = _13; m._14 = _14;
		m._21 = _21; m._22 = _22; m._23 = _23; m._24 = _24;
		m._31 = _31; m._32 = _32; m._33 = _33; m._34 = _34;
		m._41 = _41; m._42 = _42; m._43 = _43; m._44 = _44;
		return m;
	}

	inline function load(m : h3d.Matrix) {
		_11 = m._11; _12 = m._12; _13 = m._13; _14 = m._14;
		_21 = m._21; _22 = m._22; _23 = m._23; _24 = m._24;
		_31 = m._31; _32 = m._32; _33 = m._33; _34 = m._34;
		_41 = m._41; _42 = m._42; _43 = m._43; _44 = m._44;
	}
}
