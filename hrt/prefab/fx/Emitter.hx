package hrt.prefab.fx;
import hrt.impl.Gradient;
import hrt.prefab.l3d.Polygon;
import hrt.prefab.fx.Value;
import hrt.prefab.fx.Evaluator;
import hrt.prefab.fx.EmitterParam;

#if editor
import hide.prefab.HideProps;
using hrt.tools.GraphicsTools;
#end

using Lambda;

enum SimulationSpace {
	Local;
	World;
}

enum ParticleScaling {
	Parent;
	None;
}

enum SortMode {
	Depth;
	Instance;
	None;
}

enum AlignMode {
	None;
	Screen;
	Axis;
    Speed;
	ScreenSpeed;
	AxisSpeed;
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
	Dome;
	Point;
	Line;
}

enum Orientation {
	Forward;
	Normal;
	Speed;
	Random;
}

enum EmitType {
	Infinity;
	Duration;
	Burst;
	BurstDuration;
}

enum SubEmitterKind {
	SpawnOnDeath;
	Follow;
}

enum RandomColorMode {
	None;
	Colors;
	Gradient;
}

typedef PartArray = #if (hl_ver >= version("1.14.0")) hl.CArray<ParticleInstance> #else Array<ParticleInstance> #end;
typedef Single = #if (hl_ver >= version("1.13.0")) hl.F32 #else Float #end;

@:publicFields @:struct
class ParticleInstance {
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

	var subEmitters : Array<EmitterObject> = null;

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

	var idx : Int;
	var startFrame : hxd.impl.UInt16;
	var life : Single;
	var lifeTime : Single;
	var random : Single;
	var distToCam : Single;
	var startTime : Single;

	inline static var REMOVED_IDX : Int = -1;

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
		subEmitters = p.subEmitters;
	}

	function clear(emitter: EmitterObject = null) {
		if (subEmitters != null) {
			for (sub in subEmitters) {
				if( emitter != null ) {
					emitter.subEmitters = emitter.subEmitters ?? [];
					emitter.subEmitters.push(sub);
					sub.enable = false;
				} else {
					sub.remove();
				}
			}
			subEmitters = null;
		}
		if( trail != null && emitter != null && emitter.trails != null ) {
			@:privateAccess emitter.trails.disposeTrail(trail);
			trail = null;
		}
		idx = REMOVED_IDX;
	}

	function init(idx: Int, emitter: EmitterObject) {
		x = 0.0;
		y = 0.0;
		z = 0.0;
		scaleX = 1.0;
		scaleY = 1.0;
		scaleZ = 1.0;

		if(this.idx != REMOVED_IDX) emitter.error();
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

	static var tmpMat = new h3d.Matrix();
	static var tmpMat2 = new h3d.Matrix();

	inline function add( v1 : h3d.Vector, v2 : h3d.Vector4 ) {
		v1.x += v2.x;
		v1.y += v2.y;
		v1.z += v2.z;
	}

	inline function sub( v1 : h3d.Vector, v2 : h3d.Vector4 ) {
		v1.x -= v2.x;
		v1.y -= v2.y;
		v1.z -= v2.z;
	}

	inline function cross( v1 : h3d.Vector, v2 : h3d.Vector ) {
		v1.x -= v1.y * v2.z - v1.z * v2.y;
		v1.y -= v1.z * v2.x - v1.x * v2.z;
		v1.z -= v1.x * v2.y - v1.y * v2.x;
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
		var prefab = emitter.prefab;
		var v = new h3d.Vector4();
		var absPos = tmpMat;
		var localMat = tmpMat2;

		switch( prefab.alignMode ) {
			case Screen|Axis:
				if ( prefab.followRotation ) {
					inline qRot.toQuat().toMatrix(absPos);
					absPos.multiply(emitter.screenRot, absPos);
				} else
					absPos.load(emitter.screenRot);
			case ScreenSpeed:
				// qRot X axis is the speed direction (see update()), projected on the screen plane
				var n = emitter.screenRot.up();
				var dir = qRot.toQuat().getDirection();
				dir = dir - n * dir.dot(n);
				if( dir.lengthSq() < 1e-8 )
					absPos.load(emitter.screenRot);
				else
					h3d.Matrix.lookAtXInline(dir, n, absPos);
			case AxisSpeed:
				var dir = qRot.toQuat().getDirection();
				h3d.Matrix.lookAtXInline(dir, emitter.screenRot.up(), absPos);
			default:
				inline qRot.toQuat().toMatrix(absPos);
		}

		var sx = scaleX;
		var sy = scaleY;
		var sz = scaleZ;

		absPos._11 *= sx;
		absPos._12 *= sx;
		absPos._13 *= sx;
		absPos._21 *= sy;
		absPos._22 *= sy;
		absPos._23 *= sy;
		absPos._31 *= sz;
		absPos._32 *= sz;
		absPos._33 *= sz;
		absPos._41 = x;
		absPos._42 = y;
		absPos._43 = z;
		absPos.multiply3x4inline(absPos, emitter.parentTransform);

		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);

		var evaluator = emitter.evaluator;

		//SCALE
		evaluator.getFastVec(idx, emitter.partStretch, t, v);
		v.scale3(evaluator.getFast(idx, emitter.partScale, t));
		v.scale3(emitter.curScaleMultiplier);
		localMat.initScale(v.x, v.y, v.z);


		// PIVOT
		if(emitter.partPivot != VZero) {
			evaluator.getFastVec(idx, emitter.partPivot, t, v);
			localMat.tx = v.x * localMat._11;
			localMat.ty = v.y * localMat._22;
			localMat.tz = v.z * localMat._33;
		}

		// ROTATION
		if(emitter.partRotation != VZero) {
			evaluator.getFastVec(idx, emitter.partRotation, t, v);
			v.scale3(Math.PI / 180.0);
			if(v.x == 0 && v.y == 0)  // optim: most rotations are around Z only, >2x faster
				EmitterHelper.rotateZ(localMat, v.z);
			else
				localMat.rotate(v.x, v.y, v.z);
		}

		//OFFSET
		if(emitter.partOffset != VZero) {
			evaluator.getFastVec(idx, emitter.partOffset, t, v);
			localMat.tx += v.x;
			localMat.ty += v.y;
			localMat.tz += v.z;
		}

		if(emitter.baseEmitMat != null)
			localMat.multiply(emitter.baseEmitMat, localMat);

		absPos.multiply(localMat, absPos);
		this.absPos.load(absPos);
	}

	function update(emitter : EmitterObject, scene: h3d.scene.Scene, dt : Float) {
		var v = new h3d.Vector4();

		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);
		var speed = new h3d.Vector();
		speed.set(0,0,0);

		var prefab = emitter.prefab;
		var evaluator = emitter.evaluator;
		var emitOrientation = emitOrientation.toMatrix();
		var speedAccumulation = this.speedAccumulation.toVector();

		if( life == 0 ) {
			// local speed
			evaluator.getFastVec(idx, emitter.startSpeed, emitter.curTime, v);
			v.transform3x3(emitOrientation);
			add(speedAccumulation, v);
			// world speed
			evaluator.getFastVec(idx, emitter.startWorldSpeed, emitter.curTime, v);
			v.transform3x3(emitter.invTransform);
			add(speedAccumulation, v);
		}

		if(emitter.partAcceleration != VZero) {
			evaluator.getFastVec(idx, emitter.partAcceleration, t, v);
			v.scale3(dt);
			v.transform3x3(emitOrientation);
			add(speedAccumulation, v);
		}

		if(emitter.partWorldAcceleration != VZero) {
			evaluator.getFastVec(idx, emitter.partWorldAcceleration, t, v);
			v.scale3(dt);
			if(prefab.simulationSpace == Local)
				v.transform3x3(emitter.invTransform);
			add(speedAccumulation, v);
		}

		speed.x += speedAccumulation.x;
		speed.y += speedAccumulation.y;
		speed.z += speedAccumulation.z;

		if(emitter.partSpeed != VZero) {
			evaluator.getFastVec(idx, emitter.partSpeed, t, v);
			v.transform3x3(emitOrientation);
			add(speed, v);
		}

		if (emitter.partDampen != VZero) {
			var dampen = evaluator.getFast(idx, emitter.partDampen, t);
			var scale = Math.exp(dampen* -dt);
			speedAccumulation.scale(scale);
		}

		if(emitter.partWorldSpeed != VZero) {
			evaluator.getFastVec(idx, emitter.partWorldSpeed, t, v);
			if(prefab.simulationSpace == Local)
				v.transform3x3(emitter.invTransform);
			add(speed, v);
		}

		if (emitter.partMaxSpeed != VZero) {
			var maxVel = evaluator.getFast(idx, emitter.partMaxSpeed, t);
			var curVelSq = speed.lengthSq();
			if (maxVel * maxVel < curVelSq) {
				speed.normalize();
				speed.scale(maxVel);
			}
		}

		if(prefab.simulationSpace == World) {
			speed.x *= emitter.worldScale.x;
			speed.y *= emitter.worldScale.y;
			speed.z *= emitter.worldScale.z;
		}

		if (emitter.partStretchVelocity != VZero) {
			var s = evaluator.getFast(idx, emitter.partStretchVelocity, t);
			var absPos = this.absPos;
			var sx = hxd.Math.abs(speed.x * absPos._11 + speed.y * absPos._12 + speed.z * absPos._13);
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

		x += speed.x * dt;
		y += speed.y * dt;
		z += speed.z * dt;

		if(emitter.partOrbitSpeed != VZero) {
			evaluator.getFastVec(idx, emitter.partOrbitSpeed, t, v);

			var factorOverTime = emitter.curOrbitSpeedMultiplier;
			v.scale3(factorOverTime * (Math.PI / 180.0));

			tmpMat.initRotation(v.x * dt, v.y * dt, v.z * dt);

			// Rotate in emitter space and convert back to particle space
			var prevPos = getPosition();
			var pos = prevPos.clone();
			pos.transform(emitter.orbitToEmitter);
			pos.transform3x3(tmpMat);
			pos.transform(emitter.orbitFromEmitter);
			x = pos.x;
			y = pos.y;
			z = pos.z;

			// Take transform into account into local speed
			var delta = getPosition().sub(prevPos);
			delta.scale(1 / dt);
			speed.x += delta.x;
			speed.y += delta.y;
			speed.z += delta.z;
		}

		if(prefab.useCollision) {
			var plane = emitter.collisionPlane;
			var dist = plane.distance(getPosition());
			if(dist < 0) {
				var k = prefab.killOnCollision;
				if(k > 0 && (k >= 1 || emitter.random.rand() < k))
					life = lifeTime;
				var n = plane.getNormal();
				var vn = speedAccumulation.dot(n);
				var e = vn < 0 ? 1 + prefab.elasticity : 1;
				if(vn < 0) {
					speedAccumulation.x -= n.x * vn * e;
					speedAccumulation.y -= n.y * vn * e;
					speedAccumulation.z -= n.z * vn * e;
				}
				x -= n.x * dist * e;
				y -= n.y * dist * e;
				z -= n.z * dist * e;
			}
		}

		this.speedAccumulation.load(speedAccumulation);


		if((prefab.emitOrientation == Speed || prefab.alignMode == Speed || prefab.alignMode == ScreenSpeed || prefab.alignMode == AxisSpeed) && speed.lengthSq() > 0.01) {
			var q = qRot.toQuat();
			inline q.initDirection(speed);
			this.qRot.loadQuat(q);
		}

		if (subEmitters != null) {
			this.updateAbsPos(emitter);
			for (sub in subEmitters) {
				var abs = this.absPos.getPosition();
				sub.setPosition(abs.x - scene.x, abs.y - scene.y, abs.z - scene.z);
				sub.tick(dt, true);

				#if editor
				if (emitter.debugGraphics.visible) {
					emitter.debugGraphics.lineStyle(0,0xFF00FF);
					emitter.debugGraphics.drawPointCross(sub.x, sub.y, sub.z, 0.05);
				}
				#end
			}
		}
	}
}

@:access(hrt.prefab.Prefab)
@:allow(hrt.prefab.fx.ParticleInstance)
@:allow(hrt.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public var prefab : Emitter;

	// Game overrides
	public var emitScale : Float = 1.0;
	public var lifeTimeScale : Float = 1.0;

	// Emission
	public var emitRate : Value;
	public var burstParticleCount : Value;
	public var lifeTime : Value;
	public var totalBurstCount : Int = 0;

	// Emit Shape
	public var emitAngle : Value;

	// Particle Movement
	public var startSpeed : Value;
	public var startWorldSpeed : Value;
	public var partSpeed : Value;
	public var partWorldSpeed : Value;
	public var partAcceleration : Value;
	public var partWorldAcceleration : Value;
	public var partOrbitSpeed : Value;
	public var orbitSpeedMultiplier : Value;

	// Limit Velocity
	public var partDampen : Value;
	public var partMaxSpeed : Value;

	// Particle Transform
	public var partOffset : Value;
	public var partPivot : Value;
	public var partRotation : Value;
	public var partScale : Value;
	public var scaleMultiplier : Value;
	public var partStretch : Value;
	public var partStretchVelocity : Value;

	// Ground Collision
	var collisionPlane : h3d.col.Plane;

	// made from the children of the prefab
	public var particleTemplate : hrt.prefab.Object3D;
	public var subEmitterTemplates : Array<Emitter>;
	public var subEmitters : Array<EmitterObject>;
	public var trails : hrt.prefab.l3d.Trails.TrailObj;
	public var trailsTemplate : hrt.prefab.l3d.Trails;

	public var particles : PartArray;
	public var particlesCount : Int;
	public var listHead : ParticleInstance;
	var newInstances = 0;  // particles added at the head of the list since the last depth sort
	
	public var batch : h3d.scene.MeshBatch;
	public var customAnims : Array<BaseFX.CustomAnimation>;

	public var isSubEmitter : Bool = false;
	public var relativeScenePosition : Bool = false;
	public var parentEmitter : EmitterObject = null;
	public var enable : Bool;

	public var scene : h3d.scene.Scene;

	public var catchupSpeed = 4; // Use larger ticks when catching-up to save calculations
	#if !editor
	public var maxCatchupWindow = 0.5; // How many seconds max to simulate when catching up
	#end

	#if editor
	public var debugGraphics: h3d.scene.Graphics;
	public var debugShape : h3d.scene.Object;

	override function getMaterials( ?a : Array<h3d.mat.Material>, recursive = true ) {
		if( a == null ) a = [];
		if( recursive ) {
			for( o in children )
				if( o != debugShape )
					o.getMaterials(a);
		}
		return a;
	}
	#end

	public var parentNonEmitter : h3d.scene.Object;
	public var invTransform = new h3d.Matrix();
	public var screenRot = new h3d.Matrix();
	public var worldScale = new h3d.Vector(1,1,1);

	public dynamic function postParticleUpdate(particle: ParticleInstance, dt: Float) {

	}

	var random: hxd.Rand;
	var randomSeed = 0;
	var subEmitterSeed = 0;
	var emitCount = 0;
	var emitTarget = 0.0;
	var curTime = 0.0;
	// the values of the over time settings at the current tick, shared by the particles
	var curScaleMultiplier = 1.0;
	var curOrbitSpeedMultiplier = 1.0;
	var evaluator : Evaluator;
	var numInstances = 0;
	var instanceCounter = 0;
	var baseEmitterShader : hrt.shader.BaseEmitter = null;
	var animatedTextureShader : h3d.shader.AnimatedTexture = null;
	var particleShader : hrt.shader.ParticleShader = null;

	var parentTransform = new h3d.Matrix();
	var orbitToEmitter = new h3d.Matrix();
	var orbitFromEmitter = new h3d.Matrix();
	var baseEmitMat : h3d.Matrix;
	var meshTransform = new h3d.Matrix();

	public function new(?parent) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);

		#if editor
		debugGraphics = new h3d.scene.Graphics(this.getScene());
		debugGraphics.material.mainPass.setPassName("afterTonemapping");
		#end
	}

	function makeShaderInstance(prefab: hrt.prefab.Shader) {
		var shader = prefab.makeShader();
		if( shader == null )
			return;
		prefab.updateInstance();
	}

	function getParentFX() : hrt.prefab.fx.FX.FXAnimation {
		var p = parent;
		while (p != null) {
			var anim = Std.downcast(p, hrt.prefab.fx.FX.FXAnimation);
			if( anim != null ) return anim;
			p = p.parent;
		}
		return null;
	}

	override function onAdd() {
		super.onAdd();
		scene = getScene();
	}

	override function onParentChanged() {
		super.onParentChanged();
		scene = getScene();
	}

	function init(randSlots: Int, prefab: Emitter) {
		this.prefab = prefab;
		evaluator = new Evaluator();
		evaluator.allocRandom(prefab.maxCount, randSlots);
		var anim = getParentFX();
		if(anim != null)
			evaluator.parameters = @:privateAccess anim.evaluator.parameters;

		updateParentNonEmitter();

		if( batch != null )
			batch.remove();

		baseEmitMat = null;
		meshTransform.identity();
		var meshPrimitive : h3d.prim.MeshPrimitive = null;
		var meshMaterial : h3d.mat.Material = null;
		if (particleTemplate != null) {
			baseEmitMat = particleTemplate.getTransform();

			var empty3d = new h3d.scene.Object();
			var clone = particleTemplate.clone(new hrt.prefab.ContextShared(empty3d));
			#if editor
			clone.setEditor(prefab.shared.editor, prefab.shared.scene);
			#end
			@:privateAccess clone.makeInstance();
			var loc3d = Object3D.getLocal3d(clone);

			var mesh = Std.downcast(loc3d, h3d.scene.Mesh);
			if( mesh == null ) {
				for( i in 0...loc3d.numChildren ) {
					mesh = Std.downcast(loc3d.getChildAt(i), h3d.scene.Mesh);
					if( mesh != null ) {
						break;
					}
				}
			}

			if (mesh != null) {
				meshPrimitive = Std.downcast(mesh.primitive, h3d.prim.MeshPrimitive);
				meshMaterial = mesh.material;
				var absPos = mesh.getAbsPos();
				tmpMat.initInverse(baseEmitMat);
				meshTransform.multiply(absPos, tmpMat);
				if (prefab.applyMeshTransform)
					baseEmitMat.load(absPos);
				mesh.remove();
			}

			empty3d.remove();

			if(baseEmitMat.isIdentityEpsilon(0.01))
				baseEmitMat = null;
		}

		if (meshPrimitive == null ) {
			var shape : Shape = Quad(0);
			var cache = Polygon.getPrimCache();
			meshPrimitive = cache.get(shape);
			if(meshPrimitive == null) {
				var prim = Polygon.createPrimitive(shape);
				prim.incref();
				cache.set(shape, prim);
				meshPrimitive = prim;
			}
		}

		if(meshPrimitive != null ) {

			batch = new h3d.scene.MeshBatch(meshPrimitive, meshMaterial, null);
			addChildAt(batch, 0);
			batch.name = "emitter";
			batch.calcBounds = false;

			// like findAll() but skips sub-emitters and Trails
			function findRec<T:Prefab>( p : Prefab, cl : Class<T>, ?out : Array<T> ) : Array<T> {
				if( out == null ) out = [];
				for( c in p.children ) {
					if( Std.isOfType(c, Emitter) || Std.isOfType(c, hrt.prefab.l3d.Trails) )
						continue;
					var v = c.to(cl);
					if( v != null && checkEnabled(v) )
						out.push(v);
					findRec(c, cl, out);
				}
				return out;
			}

			// Setup mats
			var materials = findRec(prefab, hrt.prefab.Material);
			for( mat in materials )
				@:privateAccess mat.makeInstance();

			// Setup shaders
			customAnims = [];
			var shaders = findRec(prefab, hrt.prefab.Shader);
			for( shader in shaders ) {
				makeShaderInstance(shader);
				hrt.prefab.fx.BaseFX.BaseFXTools.getCustomAnimations(shader, customAnims, batch, true);
			}

			// Animated textures animations
			var frameCount = prefab.frameCount == 0 ? prefab.frameDivisionX * prefab.frameDivisionY : prefab.frameCount;
			if( frameCount > 1 && prefab.spriteSheet != null ) {
				var tex = hxd.res.Loader.currentInstance.load(prefab.spriteSheet).toTexture();
				var meanLifeTime = evaluator.getMean(lifeTime, 0);
				animatedTextureShader = new h3d.shader.AnimatedTexture(tex, prefab.frameDivisionX, prefab.frameDivisionY, frameCount, frameCount * prefab.animationCycles / meanLifeTime);
				animatedTextureShader.useSourceUVs = prefab.animationUseSourceUVs;
				animatedTextureShader.startTime = @:privateAccess scene?.renderer.ctx.globalTime ?? 0.0;
				animatedTextureShader.loop = prefab.animationLoop;
				animatedTextureShader.blendBetweenFrames = prefab.animationBlendBetweenFrames;
				animatedTextureShader.setPriority(1);
				batch.material.mainPass.addShader(animatedTextureShader);
			}

			baseEmitterShader = new hrt.shader.BaseEmitter();
			baseEmitterShader.meshTransform.load(meshTransform);
			baseEmitterShader.meshTransformInverse.initInverse(meshTransform);
			batch.material.mainPass.addShader(baseEmitterShader);

			particleShader = null;
			inline function getShader() {
				if( particleShader == null ) {
					particleShader = new hrt.shader.ParticleShader();
					batch.material.mainPass.addShader(particleShader);
				}
				return particleShader;
			}
			if( prefab.randomColorMode != RandomColorMode.None ) {
				var s = getShader();
				s.randomMode = prefab.randomColorMode;
				s.randomColor1.setColor(prefab.randomColor1);
				s.randomColor2.setColor(prefab.randomColor2);
				if( prefab.randomColorMode == RandomColorMode.Gradient )
					s.randomGradient = hrt.impl.Gradient.textureFromData(prefab.randomGradient, false);
			}
			if( prefab.fadeColorMode != RandomColorMode.None ) {
				var s = getShader();
				s.fadeMode = prefab.fadeColorMode;
				s.fadeColor1.setColor(prefab.fadeColor1);
				s.fadeColor2.setColor(prefab.fadeColor2);
				if( prefab.fadeColorMode == RandomColorMode.Gradient )
					s.fadeGradient = hrt.impl.Gradient.textureFromData(prefab.fadeGradient, false);
			}
			if( prefab.fadeIn > 0 || prefab.fadeOut > 0 ) {
				var s = getShader();
				s.alphaFade = true;
				s.fadeIn = prefab.fadeIn;
				s.fadeOut = prefab.fadeOut;
			}

		}

		// Dispose previous particles
		if(particles != null) {
			for(i in 0...particlesCount) {
				particles[i].clear(this);
			}
		}

		if(trails != null && trails.numTrails != prefab.maxCount) {
			trails.remove();
			trails = null;
		}

		particles = #if (hl_ver >= version("1.14.0")) hl.CArray.alloc(ParticleInstance, prefab.maxCount) #else [for(i in 0...prefab.maxCount) new ParticleInstance()] #end;
		particlesCount = prefab.maxCount;
		reset();
	}

	public static function checkEnabled(prefab: Prefab) {
		#if editor
		if (prefab.shared.editor?.isHidden(prefab) == true)
			return false;
		#end
		return prefab.enabled;
	}

	override function onRemove() {
		if (subEmitters != null) {
			for (sub in subEmitters) {
				sub.remove();
			}
			subEmitters = null;
		}

		for (i in 0...numInstances) {
			particles[i].clear(this);
		}
		numInstances = 0;
		listHead = null;

		#if editor
		debugGraphics.remove();
		#end

		scene = null;
		super.onRemove();
	}


	public function softReset() {
		totalBurstCount = 0;
		enable = true;
	}

	public function reset() {
		softReset();
		random.init(randomSeed);
		numInstances = 0;
		instanceCounter = 0;
		curTime = -prefab.delay;
		emitCount = 0;
		emitTarget = 0;
		listHead = null;

		evaluator?.resetRandom(random);

		if(particles != null) {
			for(i in 0...particlesCount) {
				particles[i].clear(this);
			}
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

	function error(?kind : String) {
		var path = name;
		var obj : h3d.scene.Object = this.parent;
		while (obj != null) {
			var name = (obj.name != null && obj.name.length > 0) ? obj.name : Type.getClassName(Type.getClass(obj));
			path = name + "/" + path;
			obj = obj.parent;
		}
		trace('curTime: $curTime, numInstances: $numInstances, emitCount: $emitCount');
		var fx = getParentFX();
		if(fx != null)
			trace("parent fx: " + fx.prefab.name);
		throw (kind != null ? kind : "emitter error") + ' ($path)';
	}

	#if emitter_check_list
	public var enableListCheck = false;
	inline function checkList() {
		if(enableListCheck)
			doCheckList();
	}

	function doCheckList() {
		var p = listHead;
		var tail = null;
		var count = 0;
		while(p != null) {
			++count;
			if(p.idx == ParticleInstance.REMOVED_IDX)
				error();
			var n = p.next;
			if(n != null)
				if(n.prev != p) error();
			if(p.next != null)
				p = p.next;
			else {
				tail = p;
				break;
			}
		}
		if(count != numInstances) error();
		p = tail;
		count = 0;
		while(p != null) {
			++count;
			p = p.prev;
		}
		if(count != numInstances) error();
	}
	#else
	inline function checkList() { }
	#end

	function allocInstance() {
		if(numInstances >= prefab.maxCount) error("allocInstance");
		var p = particles[numInstances++];
		p.init(instanceCounter, this);
		p.prev = null;
		p.next = listHead;
		if(listHead != null)
			listHead.prev = p;
		listHead = p;
		newInstances++;
		instanceCounter = (instanceCounter + 1) % prefab.maxCount;
		checkList();
		return p;
	}

	function disposeInstance(idx: Int) {
		checkList();
		if(numInstances <= 0)
			error("dispose");
		--numInstances;

		// stitch list after remove
		var o = particles[idx];

		if(o.idx == ParticleInstance.REMOVED_IDX) error("double dispose");

		// Transfer remaining subemitter to this emitter array
		o.clear(this);

		var prev = o.prev;
		var next = o.next;
		if(prev != null) {
			if(prev.next == next) error();
			prev.next = next;
		}
		else {
			if(listHead != o) error();
			if(listHead == next) error();
			listHead = next;
		}
		if(next != null) {
			if(next.prev == prev) error();
			next.prev = prev;
		}

		// remove swap
		if(idx < numInstances) {
			var swap = particles[numInstances];
			if(swap.idx == ParticleInstance.REMOVED_IDX) error();
			o.load(swap);
			swap.idx = ParticleInstance.REMOVED_IDX;
			swap.subEmitters = null;
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

		// the values are not made yet
		if( lifeTime == null )
			return;

		@:privateAccess var globalTime = scene?.renderer.ctx.globalTime ?? curTime;

		var emitterQuat : h3d.Quat = null;
		if (count > 0) {

			if (trailsTemplate != null && trails == null) {
				trails = trailsTemplate.create(this, prefab.maxCount);
				trailsTemplate.local3d = trails;
				trails.autoTrackPosition = false;
				for( mat in trailsTemplate.findAll(hrt.prefab.Material, checkEnabled) )
					@:privateAccess mat.makeInstance();
				for( shader in trailsTemplate.findAll(hrt.prefab.Shader, checkEnabled) )
					@:privateAccess shader.makeInstance();
			}

			for( i in 0...count ) {
				var part = allocInstance();
				part.startTime = globalTime;
				part.lifeTime = hxd.Math.max(0.01, evaluator.getFast(part.idx, lifeTime, curTime) * lifeTimeScale);

				tmpQuat.identity();

				switch( prefab.emitShape ) {
					case Box:
						tmpOffset.set(random.srand(0.5), random.srand(0.5), random.srand(0.5));
						if( prefab.emitSurface ) {
							var max = Math.max(Math.max(Math.abs(tmpOffset.x), Math.abs(tmpOffset.y)), Math.abs(tmpOffset.z));
							tmpOffset.scale(0.5 / max);
						}
						if( prefab.emitOrientation == Normal )
							tmpQuat.initDirection(tmpOffset);
					case Cylinder:
						var z = random.rand();
						var dx = 0.0, dy = 0.0;
						var shapeAngle = hxd.Math.degToRad(evaluator.getFloat(emitAngle, curTime)) / 2.0;
						var a = random.srand(shapeAngle);
						if(prefab.emitSurface) {
							dx = Math.cos(a)*(prefab.emitRad2*z + prefab.emitRad1*(1.0-z));
							dy = Math.sin(a)*(prefab.emitRad2*z + prefab.emitRad1*(1.0-z));
						}
						else {
							dx = Math.cos(a)*(prefab.emitRad2*z + prefab.emitRad1*(1.0-z))*random.rand();
							dy = Math.sin(a)*(prefab.emitRad2*z + prefab.emitRad1*(1.0-z))*random.rand();
						}
						tmpOffset.set(dx * 0.5, dy * 0.5, z - 0.5);
						if( prefab.emitOrientation == Normal )
							tmpQuat.initRotation(0, 0, hxd.Math.atan2(dy, dx));
					case Sphere:
						do {
							tmpOffset.x = random.srand(1.0);
							tmpOffset.y = random.srand(1.0);
							tmpOffset.z = random.srand(1.0);
						}
						while( tmpOffset.lengthSq() > 1.0 );
						if( prefab.emitSurface )
							tmpOffset.normalize();
						tmpOffset.scale(0.5);
						if( prefab.emitOrientation == Normal )
							tmpQuat.initDirection(tmpOffset);
					case Dome:
						var zMin = 1.0 - 2.0 * hxd.Math.clamp(prefab.emitDomeHeight, 0, 1);
						if( prefab.emitSurface ) {
							var z = zMin + (1.0 - zMin) * random.rand();
							var r = Math.sqrt(1.0 - z * z);
							var a = random.rand() * Math.PI * 2;
							tmpOffset.set(Math.cos(a) * r, Math.sin(a) * r, z);
						}
						else {
							var r = zMin > 0 ? Math.sqrt(1.0 - zMin * zMin) : 1.0;
							do {
								tmpOffset.x = random.srand(r);
								tmpOffset.y = random.srand(r);
								tmpOffset.z = zMin + (1.0 - zMin) * random.rand();
							}
							while( tmpOffset.lengthSq() > 1.0 );
						}
						if( prefab.emitDomeFlip )
							tmpOffset.z = -tmpOffset.z;
						tmpOffset.scale(0.5);
						if( prefab.emitOrientation == Normal )
							tmpQuat.initDirection(tmpOffset);
					case Point:
						tmpOffset.set(0, 0, 0);
						if( prefab.emitOrientation == Normal ) {
							do {
								tmpDir.x = random.srand(1.0);
								tmpDir.y = random.srand(1.0);
								tmpDir.z = random.srand(1.0);
							}
							while( tmpDir.lengthSq() > 1.0 || tmpDir.lengthSq() < 1e-6 );
							tmpQuat.initDirection(tmpDir);
						}
					case Line:
						tmpOffset.set(random.srand(0.5), 0, 0);
						if( prefab.emitOrientation == Normal ) {
							var a = random.rand() * Math.PI * 2;
							tmpDir.set(0, Math.cos(a), Math.sin(a));
							tmpQuat.initDirection(tmpDir);
						}
					case Cone:
						tmpOffset.set(0, 0, 0);
						var theta = random.rand() * Math.PI * 2;
						var shapeAngle = hxd.Math.degToRad(evaluator.getFloat(emitAngle, curTime)) / 2.0;
						var phi = shapeAngle * random.rand();
						tmpDir.x = Math.cos(phi) * scaleX;
						tmpDir.y = Math.sin(phi) * Math.sin(theta) * scaleY;
						tmpDir.z = Math.sin(phi) * Math.cos(theta) * scaleZ;
						tmpDir.normalize();
						tmpQuat.initDirection(tmpDir);
				}

				onEmit(tmpOffset, tmpQuat);

				if( prefab.emitOrientation == Random )
					tmpQuat.initRotation(random.srand(Math.PI), random.srand(Math.PI), random.srand(Math.PI));

				switch( prefab.simulationSpace ) {
					case Local:
						if(emitterQuat == null) {
							emitterQuat = tmpEmitterQuat;
							emitterQuat.load(getRotationQuat());
							tmpMat.load(getAbsPos());
							tmpMat2.load(parentNonEmitter.getAbsPos());
							tmpMat2.invert();
							tmpMat.multiply(tmpMat, tmpMat2);
							if (prefab.particleScaling == None) {
								// // Re-introduce parent scaling in the spawn position calculations
								var parentScale = inline parentNonEmitter.getAbsPos().getScale();
								tmpMat2.initScale(parentScale.x, parentScale.y, parentScale.z);
								tmpMat.multiply(tmpMat, tmpMat2);
							}
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
						if( relativeScenePosition )
							part.setPosition(tmpPt.x - scene.x, tmpPt.y - scene.y, tmpPt.z - scene.z);
						else
							part.setPosition(tmpPt.x, tmpPt.y, tmpPt.z);
						emitterQuat = tmpEmitterQuat;
						tmpMat.load(getAbsPos());
						var s = tmpMat.getScale();
						tmpMat.prependScale(1.0/s.x, 1.0/s.y, 1.0/s.z);
						emitterQuat.initRotateMatrix(tmpMat);
						emitterQuat.normalize();
						tmpQuat.multiply(emitterQuat, tmpQuat);
						part.qRot.loadQuat(tmpQuat);
						tmpQuat.toMatrix(tmpMat2);
						part.emitOrientation.load(tmpMat2);

						part.setScale(worldScale.x, worldScale.y, worldScale.z);
				}
				var frameCount = prefab.frameCount == 0 ? prefab.frameDivisionX * prefab.frameDivisionY : prefab.frameCount;
				if(prefab.animationLoop)
					part.startFrame = random.random(frameCount);

				if (subEmitterTemplates != null) {
					for (template in subEmitterTemplates) {
						if (template.subEmitterKind != SubEmitterKind.Follow) {
							continue;
						}

						var subEmitterInstance : Emitter = @:privateAccess template.make(this);
						var emitter : EmitterObject = cast subEmitterInstance.local3d;
						emitter.ignoreParentTransform = true;
						emitter.isSubEmitter = true;
						emitter.parentEmitter = this;
						emitter.setRandSeed(randomSeed + (subEmitterSeed++));
						emitter.updateParentNonEmitter();
						part.subEmitters = part.subEmitters ?? [];
						part.subEmitters.push(emitter);
					}
				}
			}
		}

		emitCount += count;
	}

	/** Called every time a particle is emitted. `offset` and `orient`
		 can be modified (local space) **/
	public dynamic function onEmit(offset: h3d.Vector, orient : h3d.Quat) { }

	function updateParentNonEmitter() {
		parentNonEmitter = parent;
		var parentEmitterTmp = parentEmitter;
		while (parentEmitterTmp != null) {
			parentNonEmitter = parentEmitterTmp.parent;
			parentEmitterTmp = parentEmitter.parentEmitter;
		}
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

	inline function getBurstCount() {
		return EmitterHelper.getBurstCount(evaluator, burstParticleCount, curTime, totalBurstCount, randomSeed);
	}

	inline function getRate() {
		return EmitterHelper.getRate(evaluator, emitRate, curTime, prefab.emitRateChangeTime, randomSeed);
	}

	function tick( dt : Float, full=true) {
		if (scene == null)
			scene = getScene();

		#if editor
		debugGraphics.clear();
		#end

		// Auto remove of sub emitters: a Follow one is in the list of its particle until the particle dies
		if( !enable && (particles == null || numInstances <= 0) && isSubEmitter && parentEmitter.subEmitters?.remove(this) == true ) {
			remove();
			return;
		}

		curScaleMultiplier = evaluator.getFloat(scaleMultiplier, curTime);
		curOrbitSpeedMultiplier = evaluator.getFloat(orbitSpeedMultiplier, curTime);

		if(subEmitters != null) {
			for( se in subEmitters ) {
				se.tick(dt);
				#if editor
				if (debugGraphics.visible) {
					debugGraphics.lineStyle(0,0x770077);
					debugGraphics.drawPointCross(se.x, se.y, se.z, 0.05);
				}
				#end
			}
		}

		if( emitRate == null )
			return;

		if( parentNonEmitter != null ) {
			if (prefab.particleScaling == None) {
				worldScale.set(1.0,1.0,1.0);
			}
			else {
				worldScale.load(parentNonEmitter.getAbsPos().getScale());
			}
			invTransform.load(parentNonEmitter.getInvPos());
		}

		if( enable && emitScale > 0. && curTime >= 0) {
			switch prefab.emitType {
				case Infinity:
					emitTarget += getRate() * hxd.Math.clamp(emitScale) * dt;
					var delta = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - numInstances, emitTarget - emitCount));
					doEmit(delta);
					if( isSubEmitter && (parentEmitter == null || parentEmitter.parent == null) )
						enable = false;
				case Duration:
					if( curTime < prefab.emitDuration ) {
						emitTarget += getRate() * hxd.Math.clamp(emitScale) * dt;
						var delta = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - numInstances, emitTarget - emitCount));
						doEmit(delta);
					}
					if( isSubEmitter && curTime >= prefab.emitDuration )
						enable = false;
				case BurstDuration:
					if( prefab.burstInterval > 0 ) {
						var burstTarget = 1 + hxd.Math.floor(curTime / prefab.burstInterval);
						var lastBurstTime = totalBurstCount * prefab.burstInterval;
						var nextBurstTime = lastBurstTime + prefab.burstInterval;
						var needBurst = nextBurstTime <= prefab.emitDuration && totalBurstCount < burstTarget;
						while( needBurst ) {
							var delta = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - numInstances, getBurstCount()));
							doEmit(delta);
							totalBurstCount++;
							lastBurstTime += prefab.burstInterval;
							nextBurstTime = lastBurstTime + prefab.burstInterval;
							needBurst = nextBurstTime <= prefab.emitDuration && totalBurstCount < burstTarget;
						}
					}
					if( isSubEmitter && curTime > prefab.emitDuration )
						enable = false;
				case Burst:
					if( prefab.burstInterval > 0 ) {
						var burstTarget = hxd.Math.min(prefab.burstCount, 1 + hxd.Math.floor(curTime / prefab.burstInterval));
						while( totalBurstCount < burstTarget ) {
							var delta = hxd.Math.ceil(hxd.Math.min(prefab.maxCount - numInstances, getBurstCount()));
							doEmit(delta);
							totalBurstCount++;
						}
					}
					if( isSubEmitter && totalBurstCount == prefab.burstCount )
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
		if(prefab.alignMode == Screen || prefab.alignMode == ScreenSpeed || prefab.alignMode == AxisSpeed) {
			var cam = scene?.camera;
			if (cam == null)
				return;
			tmpMat.load(cam.mcam);
			tmpMat.invert();

			if(prefab.simulationSpace == Local) {  // Compensate parent rotation
				tmpMat2.load(parentNonEmitter.getAbsPos());
				var s = tmpMat2.getScale();
				tmpMat2.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
				tmpMat2.invert();
				tmpMat.multiply(tmpMat, tmpMat2);
			}

			screenRot.initRotationAxis( new h3d.Vector(1,0,0),Math.PI);  // Flip Y axis so Y is pointing down
			screenRot.multiply(screenRot, tmpMat);
		}
		else if(prefab.alignMode == Axis) {
			var cam = scene?.camera;
			if (cam == null)
				return;
			var lockAxis = new h3d.Vector();
			var rightAxis = new h3d.Vector();
			var upAxis = new h3d.Vector();
			switch prefab.alignLockAxis {
				case X:
					lockAxis.set(1, 0, 0);
					rightAxis.set(0, 1, 0);
					upAxis.set(0, 0, 1);
				case Y:
					lockAxis.set(0, 1, 0);
					rightAxis.set(0, 0, 1);
					upAxis.set(1, 0, 0);
				case Z:
					lockAxis.set(0, 0, 1);
					rightAxis.set(1, 0, 0);
					upAxis.set(0, 1, 0);
				case ScreenZ:
					lockAxis.set(0, 0, 1);
					rightAxis.set(0, 1, 0);
					upAxis.set(-1, 0, 0);
			}
			var lookAtPos = tmpVec;
			lookAtPos.load(cam.pos);

			if ( prefab.followRotation ) {
				var invAbsPos = getInvPos();
				lookAtPos.transform(invAbsPos);
			} else {
				var invParent = parentNonEmitter.getInvPos();
				lookAtPos.transform(invParent);
				lookAtPos.x -= x;
				lookAtPos.y -= y;
				lookAtPos.z -= z;
			}

			lookAtPos.x *= lockAxis.x != 0.0 ? 0.0 : 1.0;
			lookAtPos.y *= lockAxis.y != 0.0 ? 0.0 : 1.0;
			lookAtPos.z *= lockAxis.z != 0.0 ? 0.0 : 1.0;
			lookAtPos.normalize();

			var angle = hxd.Math.acos(rightAxis.dot(lookAtPos));
			if(upAxis.dot(lookAtPos) < 0)
				angle = -angle;

			screenRot.initRotationAxis(lockAxis, angle);
			if(prefab.alignLockAxis == ScreenZ) {
				tmpMat.initRotationAxis(new h3d.Vector(1.0, 0.0, 0.0),-Math.PI/2);
				screenRot.multiply(tmpMat, screenRot);
			}
		}
	}

	static function sortZ( p1 : ParticleInstance, p2 : ParticleInstance ) : Int {
		return p1.distToCam < p2.distToCam ? 1 : -1;
	}

	function depthSort() {
		checkList();
		listHead = EmitterHelper.depthSort(listHead, newInstances, numInstances * 2, sortZ);
		newInstances = 0;
		checkList();
	}

	function updateMeshBatch() {
		if(batch == null) return;
		batch.begin(hxd.Math.nextPOT(prefab.maxCount));

		inline function emit(p: ParticleInstance) {
			if (p.life > p.lifeTime)
				return;
			inline tmpMat.load(p.absPos.toMatrix());
			batch.worldPosition = tmpMat;
						for( anim in customAnims ) {
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

			batch.emitInstance();
		}

		switch(prefab.sortMode) {
			case Depth:
					depthSort();
					var p = listHead;
					while(p != null) {
						emit(p);
						p = p.next;
					}
			case Instance:
				var p = listHead;
				while(p != null) {
					emit(p);
					p = p.next;
				}
			case None:
				for(i in 0...numInstances)
					emit(particles[i]);
		}
	}

	function updateParticles(full: Bool, dt: Float) {
		if (scene == null)
			return;

		switch(prefab.simulationSpace){
			// Particles in Local are spawned next to emitter in the scene tree,
			// so emitter shape can be transformed (especially scaled) without affecting children
			case Local : parentTransform.load(parentNonEmitter.getAbsPos());
			case World : parentTransform.load(scene.getAbsPos());
			// Optim: set to null if identity to skip multiply in particle updates
		}

		if (prefab.particleScaling == None) {
			var scale = parentTransform.getScale();
			parentTransform.scale(1.0/scale.x, 1.0/scale.y, 1.0/scale.z);
		}

		if (prefab.useCollision) {
			var m = new h3d.Matrix();
			m.initInverse(parentTransform);
			m.multiply(parentNonEmitter.getAbsPos(), m);
			collisionPlane = h3d.col.Plane.Z();
			collisionPlane.transform(m);
			collisionPlane.normalize();
		}

		// Particle space <-> emitter space, for orbit speed
		if (partOrbitSpeed != VZero) {
			orbitToEmitter.multiply(parentTransform, getInvPos());
			orbitFromEmitter.initInverse(orbitToEmitter);
		}

		var camPos = scene.camera.pos;

		checkList();
		var i = 0;
		while(i < numInstances) {
			var p = particles[i];
			if(p.life > p.lifeTime) {
				if (trails != null && p.trail != null && p.trail.numPoints > 0) {
					// trail still fading out, keep particle slot alive until all points expire
					var pos = p.absPos.getPosition();
					trails.updateTrail(p.trail, dt, pos.x, pos.y, pos.z);
					++i;
				} else {
					// SUB EMITTER
					if( subEmitterTemplates != null ) {
						for (template in subEmitterTemplates) {
							if (template.subEmitterKind != SubEmitterKind.SpawnOnDeath) {
								continue;
							}
							var subEmitterInstance : Emitter = @:privateAccess template.make(scene);
							var emitter : EmitterObject = cast subEmitterInstance.local3d;
							p.updateAbsPos(this);
							var pos = p.absPos.getPosition();
							emitter.setPosition(pos.x - scene.x, pos.y - scene.y, pos.z - scene.z);
							emitter.isSubEmitter = true;
							emitter.parentEmitter = this;
							emitter.setRandSeed(randomSeed + (subEmitterSeed++));
							if(subEmitters == null)
								subEmitters = [];
							subEmitters.push(emitter);
						}
					}
					i = disposeInstance(i);
				}
			}
			else {
				p.update(this, scene, dt);
				postParticleUpdate(p, dt);

				if(full) {
					p.updateAbsPos(this);
					if(p.distToCam < 0 || prefab.sortMode == Depth)
						p.distToCam = camPos.distanceSq(p.absPos.getPosition());
				}
				p.life += dt;  // After updateAbsPos(), which uses current life
				++i;

				if (trails != null) {
					var pos = p.absPos.getPosition();
					trails.updateTrail(p.trail, dt, pos.x, pos.y, pos.z);
				}
			}
		}
		checkList();
	}

	public function hasActiveParts() : Bool {
		if(particles == null)
			return false;

		inline function isActive(p : ParticleInstance){
			return p.idx != ParticleInstance.REMOVED_IDX && p.life <= p.lifeTime;
		}

		for(i in 0...particlesCount){
			var p = particles[i];
			if(isActive(p))
				return true;
		}

		return false;
	}

	public function setRandSeed(seed: Int) {
		randomSeed = seed ^ prefab.seed;
		reset();
	}

	#if editor
	public var tickTime : Float = 0;
	#end


	var lastParentTime = 0.0;
	public function setTime(parentTime: Float, dt: Float, seek: Bool, full: Bool) {
		var localTime = (parentTime-prefab.delay) * prefab.timeScale;
		if (!full) {
			curTime = localTime;
			return;
		}

		if (seek && parentTime < lastParentTime) {
			reset();
			updateMeshBatch();  // Make sure mesh batch is reset even when no tick is called()
			#if !editor
			curTime = localTime;
			#else
			if (localTime < 0) {
				curTime = localTime;
			}
			#end
		}
		else if (!seek) {
			if (parentTime < lastParentTime) {
				softReset();
				// the bursts before this tick are done, the ones since the start of the loop are emitted by it
				if (prefab.burstInterval > 0)
					totalBurstCount = hxd.Math.ceil(hxd.Math.max(0.0, (localTime - dt * prefab.timeScale) / prefab.burstInterval));
				if (prefab.emitType == Burst) {
					if (totalBurstCount >= prefab.burstCount)
						enable = false;
				} else if (prefab.emitType == BurstDuration) {
					if (localTime > prefab.emitDuration)
						enable = false;
				}

				curTime = localTime;
			}
		}
		lastParentTime = parentTime;

		var abs = this.getAbsPos();
		baseEmitterShader.emitPosition.set(abs.tx, abs.ty, abs.tz);

		var time = localTime + prefab.warmUpTime;
		var catchupTime = time - curTime;

		var seek = seek || (catchupTime > 1.5 * dt);

		if (!seek) {
			if (dt == 0)
				return;
			#if editor
			var start = haxe.Timer.stamp();
			#end
			tick(dt * prefab.timeScale, true);
			#if editor
			var end = haxe.Timer.stamp();
			tickTime = end - start;
			#end
			return;
		}


		if(hxd.Math.abs(time - curTime) < 1e-6) {  // Time imprecisions can occur during accumulation
			updateAlignment();
			for(i in 0...numInstances)
				particles[i].updateAbsPos(this);
			updateMeshBatch();
			return;
		}


		#if !editor  // Limit catchup time to avoid spikes when showing long running FX
		var longCatchup = catchupTime > maxCatchupWindow;
		if(longCatchup) {
			var firstWarmup = curTime <= 0.0 && prefab.warmUpTime > 0;
			catchupTime = firstWarmup ? prefab.warmUpTime : maxCatchupWindow;
			curTime = time - catchupTime;
			emitCount = hxd.Math.ceil(EmitterHelper.getRateSum(evaluator, emitRate, prefab.emitType == Duration ? Math.min(curTime, prefab.emitDuration) : curTime));

			// Force sort after long time invisible
			for(i in 0...numInstances)
				particles[i].distToCam = -1;
		}
		#end

		var catchupTickRate = hxd.Timer.wantedFPS * prefab.timeScale / catchupSpeed;
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

	override function addBoundsRec( b : h3d.col.Bounds, relativeTo : h3d.Matrix ) {
		if( posChanged ) {
			posChanged = false;
			calcAbsPos();
		}
	}
}

@:prefabName("Emitter")
@:prefabIcon(hrt.ui.HuiRes.ui.icons.prefab.emitter)
@:build(hrt.prefab.fx.EmitterMacros.build("hrt.prefab.fx.Emitter.EmitterObject"))
class Emitter extends Object3D implements hrt.prefab.fx.EmitterParam.IEmitter {

	@:group("Properties")
	@:s @:range(0, null) @:disp("Time Scale", "Time multiplier of the simulation")
	public var timeScale : Float = 1.0;
	@:s @:range(0, null) @:disp("Start Delay", "Time before the start of the emitter, in seconds")
	public var delay : Float = 0.0;
	@:s @:range(0, null) @:disp("Warm Up", "Time simulated before the start, in seconds: the emitter starts already filled")
	public var warmUpTime : Float = 0.0;
	@:s @:range(0, null) @:disp("Seed", "Changes the random values of the emitter, to differentiate two identical emitters")
	public var seed : Int = 0;
	@:s @:disp("Simulation Space", "Local: the particles move with the emitter. World: once emitted, they no longer follow it")
	public var simulationSpace : SimulationSpace = SimulationSpace.Local;
	@:s @:disp("Particle Scaling", "Whether the particles are scaled by the parents of the emitter")
	public var particleScaling : ParticleScaling = ParticleScaling.Parent;
	@:s @:disp("Apply Mesh Transform", "The particles take the transform of the mesh of the emitter")
	public var applyMeshTransform : Bool = false;
	@:s @:disp("Sort Mode", "Depth: back to front from the camera. Instance: in their emission order. None: not sorted")
	public var sortMode : SortMode = SortMode.Depth;
	@:s @:disp("Sub Emitter Mode", "For a sub emitter: spawned at the death of each particle of its parent, or following each of them")
	public var subEmitterKind : SubEmitterKind = SubEmitterKind.SpawnOnDeath;

	@:group("Emission")
	@:s @:disp("Type", "Infinity: emits at its rate. Duration: emits at its rate during a duration. Burst / Burst Duration: groups of particles at regular intervals")
	public var emitType : EmitType = EmitType.Infinity;
	@:s @:range(0, null) @:disp("Duration", "Emission duration, in seconds")
	public var emitDuration : Float = 1.0;
	@:param(PFloat(0), Emission, 5.) @:disp("Rate", "Number of particles emitted per second. A Range changes it at random between min and max, every Rate Change Time")
	public var emitRate : ParamMode;
	@:s @:range(0.01, null) @:disp("Rate Change Time", "Random rate: every this many seconds a new random rate is picked between min and max, and the rate goes to it during this time")
	public var emitRateChangeTime : Float = 1.0;
	@:s @:range(1, null) @:disp("Burst Count", "Number of bursts")
	public var burstCount : Float = 1;
	@:s @:range(0, null) @:disp("Burst Interval", "Time between two bursts, in seconds")
	public var burstInterval : Float = 1.0;
	@:param(PFloat(1), Emission, 1.) @:disp("Particles Per Burst", "Number of particles emitted by each burst. A Range draws it for each burst, between min and max")
	public var burstParticleCount : ParamMode;
	@:s @:range(0, null) @:disp("Max Count", "Maximum number of particles alive at the same time: no particle is emitted beyond")
	public var maxCount : Int = 20;
	@:param(PFloat(0), Spawn, 1.) @:disp("Lifetime", "Life duration of the particle, in seconds")
	public var lifeTime : ParamMode;

	@:group("Emit Shape")
	@:s @:disp("Shape", "Volume in which the particles are emitted")
	public var emitShape : EmitShape = EmitShape.Sphere;
	@:s @:range(0, 360.0) @:animate @:disp("Angle", "Opening angle of the cone, or angle of the cylinder sector, in degrees")
	public var emitAngle : Float = 30.0;
	@:s @:range(0, null) @:disp("Bottom Radius", "Radius of the bottom of the cylinder")
	public var emitRad1 : Float = 1.0;
	@:s @:range(0, null) @:disp("Top Radius", "Radius of the top of the cylinder")
	public var emitRad2 : Float = 1.0;
	@:s @:range(0, null) @:disp("Dome Height", "Height of the dome: 0.5 for a half sphere, 1 for a full sphere")
	public var emitDomeHeight : Float = 0.5;
	@:s @:disp("Flip Dome", "Flips the dome upside down")
	public var emitDomeFlip : Bool = false;
	@:s @:disp("Surface", "Emits on the surface of the shape instead of in its volume")
	public var emitSurface : Bool = false;
	@:s @:disp("Orientation", "Initial orientation of the particles: the emitter one, the normal of the shape, their speed, or random")
	public var emitOrientation : Orientation = Orientation.Forward;

	@:group("Particle Movement")
	@:param(PVec(3), Spawn) @:disp("Start Speed", "Initial speed in the emitter orientation, set at the spawn of the particle")
	public var startSpeed : ParamVec3;
	@:param(PVec(3), Spawn) @:disp("Start World Speed", "Initial speed in world space, set at the spawn of the particle")
	public var startWorldSpeed : ParamVec3;
	@:param(PVec(3), Particle) @:disp("Constant Speed", "Speed in the emitter orientation, added to the velocity without being accumulated")
	public var partSpeed : ParamVec3;
	@:param(PVec(3), Particle) @:disp("Constant World Speed", "Speed in world space, added to the velocity without being accumulated")
	public var partWorldSpeed : ParamVec3;
	@:param(PVec(3), Particle) @:disp("Acceleration", "Acceleration in the emitter orientation, accumulated in the velocity")
	public var partAcceleration : ParamVec3;
	@:param(PVec(3), Particle) @:disp("World Acceleration", "Acceleration in world space (gravity, wind...), accumulated in the velocity")
	public var partWorldAcceleration : ParamVec3;
	@:param(PVec(3, -360, 360), Particle) @:disp("Orbit Speed", "Rotation speed around the emitter, in degrees per second")
	public var partOrbitSpeed : ParamVec3;
	@:s @:range(0, null) @:animate @:disp("Orbit Speed Multiplier", "Multiplier of the orbit speed of all the particles, animated over the emitter time")
	public var orbitSpeedMultiplier : Float = 1;

	@:group("Limit Velocity")
	@:param(PFloat(0), Particle) @:disp("Dampen", "Damping of the accumulated velocity (start speed and accelerations), per second")
	public var partDampen : ParamMode;
	@:param(PFloat(0), Particle) @:disp("Max Speed", "Maximum speed of the particle")
	public var partMaxSpeed : ParamMode;

	@:group("Particle Transform")
	@:param(PVec(3), Particle) @:disp("Offset", "Offset of the particle position, without effect on its movement")
	public var partOffset : ParamVec3;
	@:param(PVec(3), Particle) @:disp("Pivot", "Pivot of the particle, relative to its size")
	public var partPivot : ParamVec3;
	@:param(PVec(3, 0, 360), Particle) @:disp("Rotation", "Rotation of the particle, in degrees")
	public var partRotation : ParamVec3;
	@:param(PFloat(), Particle, 1.) @:disp("Scale", "Uniform scale of the particle")
	public var partScale : ParamMode;
	@:s @:range(0, null) @:animate @:disp("Scale Multiplier", "Multiplier of the scale of all the particles, animated over the emitter time")
	public var scaleMultiplier : Float = 1;
	@:param(PVec(3), Particle, [1., 1., 1.]) @:disp("Stretch", "Scale of the particle on each of its axes")
	public var partStretch : ParamVec3;
	@:param(PFloat(0), Particle) @:disp("Stretch By Velocity", "Stretches the particle along its velocity")
	public var partStretchVelocity : ParamMode;

	@:group("Alignment")
	@:s @:disp("Align Mode", "Alignment of the particles: none, facing the screen, around an axis, or along their speed")
	public var alignMode : AlignMode = AlignMode.None;
	@:s @:disp("Lock Axis", "Axis around which the particles rotate to face the camera")
	public var alignLockAxis : AlignLockAxis = AlignLockAxis.ScreenZ;
	@:s @:disp("Follow Rotation", "The aligned particles keep their own rotation and the one of the emitter")
	public var followRotation : Bool = false;

	@:group("Color")
	@:s @:disp("Random Color", "Multiplies the color of each particle (alpha included) by a random color, taken between two colors or in a gradient")
	public var randomColorMode : RandomColorMode = RandomColorMode.None;
	@:s @:t(PColor) @:disp("Color 1", "First bound of the random color")
	public var randomColor1 : Int = 0xFF000000;
	@:s @:t(PColor) @:disp("Color 2", "Second bound of the random color")
	public var randomColor2 : Int = 0xFFFFFFFF;
	@:s @:disp("Gradient", "Gradient in which the random color is taken")
	public var randomGradient : GradientData;
	@:s @:disp("Fade Color", "Multiplies the color of each particle (alpha included) by a color faded over its life, from a color to another or along a gradient")
	public var fadeColorMode : RandomColorMode = RandomColorMode.None;
	@:s @:t(PColor) @:disp("Start Color", "Color at the birth of the particle")
	public var fadeColor1 : Int = 0xFFFFFFFF;
	@:s @:t(PColor) @:disp("End Color", "Color at the death of the particle")
	public var fadeColor2 : Int = 0x00FFFFFF;
	@:s @:disp("Gradient", "Gradient along which the color fades, over the life of the particle")
	public var fadeGradient : GradientData;
	@:s @:range(0, 1) @:disp("Fade In", "Part of the particle life over which its alpha goes from 0 to 1, at its birth (0: none)")
	public var fadeIn : Float = 0;
	@:s @:range(0, 1) @:disp("Fade Out", "Part of the particle life over which its alpha goes from 1 to 0, before its death (0: none)")
	public var fadeOut : Float = 0;

	@:group("Sprite Sheet Animation")
	@:s @:t(PFile(["jpg", "png"])) @:disp("Sheet", "Texture containing the frames of the animation")
	public var spriteSheet : String;
	@:s @:range(0) @:disp("Frames", "Number of frames, 0 for all the cells of the sheet")
	public var frameCount : Int = 0;
	@:s @:range(1) @:disp("Divisions X", "Number of columns of the sheet")
	public var frameDivisionX : Int = 1;
	@:s @:range(1) @:disp("Divisions Y", "Number of rows of the sheet")
	public var frameDivisionY : Int = 1;
	@:s @:range(0, 2.0) @:disp("Cycles", "Number of times the animation is played during the life of a particle")
	public var animationCycles : Float = 1.0;
	@:s @:disp("Loop", "Loops the animation, each particle starting on a random frame")
	public var animationLoop : Bool = true;
	@:s @:disp("Use Source UV", "Keeps the UVs of the mesh inside each frame")
	public var animationUseSourceUVs : Bool = true;
	@:s @:disp("Blend Frames", "Blends two consecutive frames for a smooth animation")
	public var animationBlendBetweenFrames : Bool = true;

	@:group("Ground Collision")
	@:s @:disp("Use Collision", "The particles bounce on the ground plane")
	public var useCollision : Bool = false;
	@:s @:range(0, 1.0) @:disp("Elasticity", "Bounce of the particles: 0 makes them slide on the ground, 1 bounces them with their whole speed")
	public var elasticity : Float = 1.0;
	@:s @:range(0, 1.0) @:disp("Kill Chance On Collision", "Probability for a particle to die when it touches the ground")
	public var killOnCollision : Float = 0.0;

	@:group("Debug")
	@:s @:disp("Show Debug", "Draws a cross at the position of each sub emitter")
	public var viewDebug : Bool = false;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		applyMeshTransform = true;  // old emitters stay false, new ones true by default
	}

	override function save() {
		var data = super.save();
		saveParams(data);
		if( randomColorMode != RandomColorMode.Gradient )
			Reflect.deleteField(data, "randomGradient");
		if( fadeColorMode != RandomColorMode.Gradient )
			Reflect.deleteField(data, "fadeGradient");
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
		// Negative warmup time is an old version of delay
		if( warmUpTime < 0 ) {
			delay = -warmUpTime;
			warmUpTime = 0;
		}
		if( randomGradient == null && randomColorMode == RandomColorMode.Gradient )
			randomGradient = hrt.impl.Gradient.getDefaultGradientData();
		if( fadeGradient == null && fadeColorMode == RandomColorMode.Gradient )
			fadeGradient = hrt.impl.Gradient.getDefaultGradientData();
	}

	override function copy(obj:Prefab) {
		super.copy(obj);
		copyParams(cast obj);
	}

	override function getPreloadFiles():Array<String> {
		var files = super.getPreloadFiles();
		if( spriteSheet != null ) files.push(spriteSheet);
		return files;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var emitterObj = Std.downcast(local3d, EmitterObject);

		// if we are in a subEmitter
		if (emitterObj == null) {
			parent.updateInstance();
			return;
		}

		var template : Object3D = cast children.find(
			c -> EmitterObject.checkEnabled(c) &&
			(c.name == null || c.name.indexOf("collision") == -1) &&
			c.to(Object3D) != null &&
			c.to(Object3D).visible &&
			c.to(Emitter) == null &&
			c.to(hrt.prefab.l3d.Trails) == null);

		var params = makeValues(emitterObj);
		emitterObj.particleTemplate = template;

		// SUB-EMITTER
		var subEmitterTemplates : Array<Prefab> = children.filter( p -> EmitterObject.checkEnabled(p) && Std.downcast(p, Emitter) != null && p.to(Object3D).visible);
		emitterObj.subEmitterTemplates = subEmitterTemplates.length > 0 ? [for (s in subEmitterTemplates) cast s] : null;

		// TRAILS
		var trailsTemplate : hrt.prefab.l3d.Trails = cast children.find(p -> EmitterObject.checkEnabled(p) && Std.isOfType(p, hrt.prefab.l3d.Trails) && p.to(Object3D).visible);
		emitterObj.trailsTemplate = trailsTemplate;

		// DEBUG
		#if editor
		emitterObj.debugGraphics.visible = viewDebug;
		#end

		emitterObj.init(params.randomSlots, this);

		#if editor
		if(propName == null || ["emitShape", "emitAngle", "emitRad1", "emitRad2", "emitDomeHeight", "emitDomeFlip"].indexOf(propName) >= 0)
			updateEmitShape(emitterObj);
		#end
	}

	override function makeChild(p:Prefab) {
	};

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		return new EmitterObject(parent3d);
	}

	#if (editor || editor_hl)

	override function onEditorTreeChanged(child: Prefab) : hrt.prefab.Prefab.TreeChangedResult {
		return Rebuild;
	}

	static var REFRESH_PARAMS = ["emitShape", "alignMode", "useCollision", "emitType", "randomColorMode", "fadeColorMode"];

	function getHiddenFields() : Array<String> {
		var hidden = [];
		inline function hide(name: String)
			hidden.push(name);

		if(!(emitShape == Cone || emitShape == Cylinder))
			hide("emitAngle");
		if(emitShape != Cylinder) {
			hide("emitRad1");
			hide("emitRad2");
		}
		if(emitShape != Dome) {
			hide("emitDomeHeight");
			hide("emitDomeFlip");
		}
		if(emitShape == Point || emitShape == Line)
			hide("emitSurface");

		switch(alignMode) {
			case None | Screen | Speed | ScreenSpeed | AxisSpeed:
				hide("alignLockAxis");
			default:
		}

		var isSub = findParent(Emitter) != null;
		if (!isSub) {
			hide("subEmitterKind");
		}

		if( !useCollision ) {
			hide("elasticity");
			hide("killOnCollision");
		}

		if(randomColorMode != RandomColorMode.Colors) {
			hide("randomColor1");
			hide("randomColor2");
		}
		if(randomColorMode != RandomColorMode.Gradient)
			hide("randomGradient");
		if(fadeColorMode != RandomColorMode.Colors) {
			hide("fadeColor1");
			hide("fadeColor2");
		}
		if(fadeColorMode != RandomColorMode.Gradient)
			hide("fadeGradient");

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

	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		function onChange(pname: String, isTemp: Bool) {
			if (pname == "randomColorMode")
				randomGradient = randomColorMode == RandomColorMode.Gradient ? hrt.impl.Gradient.getDefaultGradientData() : null;
			if (pname == "fadeColorMode")
				fadeGradient = fadeColorMode == RandomColorMode.Gradient ? hrt.impl.Gradient.getDefaultGradientData() : null;
			if (pname == "warmUpTime" && warmUpTime < 0) {
				warmUpTime = 0;
				ctx.quickError("Warm up time can no longer be negative. Use the Delay property instead");
			}
			ctx.rebuildPrefab(this);
			if (!isTemp && REFRESH_PARAMS.contains(pname))
				ctx.rebuildInspector();
		}

		EmitterHelper.edit(ctx, this, getHiddenFields(), onChange);
	}

	#if editor

	override function setSelected(b : Bool ) {
		var emitterObj = Std.downcast(local3d, EmitterObject);
		if(emitterObj == null)
			return false;
		if(emitterObj.debugShape != null)
			emitterObj.debugShape.visible = b;

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

		var debugShape = emitterObj.debugShape;
		if(debugShape == null) {
			debugShape = new h3d.scene.Object(emitterObj);
			debugShape.name = "_highlight";
			debugShape.visible = false;
			emitterObj.debugShape = debugShape;
		}

		debugShape.removeChildren();

		var mesh : h3d.scene.Mesh = null;
		switch(emitShape) {
			case Cylinder: {
				var rad1 = emitRad1 * 0.5;
				var rad2 = emitRad2 * 0.5;
				var angle = hxd.Math.degToRad(emitAngle);

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
				var angle = hxd.Math.degToRad(emitAngle) / 2.0;
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
			case Point, Line: {
				var g = new h3d.scene.Graphics(debugShape);
				g.material.mainPass.setPassName("overlay");
				g.lineStyle(1, 0xffffff);
				g.moveTo(-0.5, 0, 0);
				g.lineTo(0.5, 0, 0);
				if(emitShape == Point) {
					g.moveTo(0, -0.5, 0);
					g.lineTo(0, 0.5, 0);
					g.moveTo(0, 0, -0.5);
					g.lineTo(0, 0, 0.5);
				}
				g.ignoreCollide = true;
				mesh = g;
			}
			case Dome: {
				var maxPhi = Math.acos(1.0 - 2.0 * hxd.Math.clamp(emitDomeHeight, 0, 1));
				var sz = emitDomeFlip ? -0.5 : 0.5;
				var g = new h3d.scene.Graphics(debugShape);
				inline function pt(phi : Float, t : Float, first : Bool) {
					var r = Math.sin(phi) * 0.5;
					if(first)
						g.moveTo(Math.cos(t) * r, Math.sin(t) * r, Math.cos(phi) * sz);
					else
						g.lineTo(Math.cos(t) * r, Math.sin(t) * r, Math.cos(phi) * sz);
				}
				g.material.mainPass.setPassName("overlay");
				g.lineStyle(1, 0xffffff);
				for(j in 0...4) {
					var phi = maxPhi * (4 - j) / 4;
					for(i in 0...33)
						pt(phi, i / 32 * Math.PI * 2, i == 0);
				}
				for(k in 0...8) {
					var t = k / 8 * Math.PI * 2;
					for(i in 0...17)
						pt(maxPhi * i / 16, t, i == 0);
				}
				g.ignoreCollide = true;
				mesh = g;
			}
		}

		if(mesh != null) {
			var mat = mesh.material;
			mat.mainPass.setPassName("overlay");
			mat.shadows = false;
		}

		return debugShape;
	}

	function onChildUpdate(p: Prefab) {
		shared.editor.queueRebuild(this);
	}

	override function getHideProps() : HideProps {
		return { icon : "asterisk", name : "Emitter", allowParent : function(p) return p.to(FX) != null || p.findParent(FX) != null, onChildUpdate: onChildUpdate};
	}
	#end

	static var _ = Prefab.register("emitter", Emitter);

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

	inline function load(v: h3d.Vector4) {
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
		return new h3d.Vector4(x, y, z, w);
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
		v.set(_41,_42,_43);
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
