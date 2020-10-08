package hrt.prefab.fx;
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

typedef InstanceDef = {
	localSpeed: Value,
	worldSpeed: Value,
	startSpeed: Value,
	startWorldSpeed: Value,
	acceleration: Value,
	worldAcceleration: Value,
	localOffset: Value,
	scale: Value,
	stretch: Value,
	rotation: Value,
	color: Value,
}

typedef EmitterTrail = {
	particle : ParticleInstance,
	trail : h3d.scene.Trail,
	timeBeforeDeath : Float
}

typedef ShaderAnims = Array<ShaderAnimation>;

private class ParticleTransform {

	public var parent : h3d.scene.Object;
	public var absPos = new h3d.Matrix();
	public var qRot = new h3d.Quat();
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;
	public var scaleX = 1.0;
	public var scaleY = 1.0;
	public var scaleZ = 1.0;

	public function new() {

	}

	public function reset() {
		x = 0.0;
		y = 0.0;
		z = 0.0;
		scaleX = 1.0;
		scaleY = 1.0;
		scaleZ = 1.0;
	}

	public function setRotation( quat ) {
		qRot.load(quat);
	}

	public function setPosition( x, y, z ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	public function calcAbsPos() {
		qRot.toMatrix(absPos);
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
		if( parent != null )
			absPos.multiply3x4inline(absPos, parent.getAbsPos());
	}

	static var tmpMat = new h3d.Matrix();
	static var tmpVec = new h3d.Vector();
	public function setTransform( mat : h3d.Matrix ) {
		var s = mat.getScale(tmpVec);
		this.x = mat.tx;
		this.y = mat.ty;
		this.z = mat.tz;
		this.scaleX = s.x;
		this.scaleY = s.y;
		this.scaleZ = s.z;
		tmpMat.load(mat);
		tmpMat.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
		qRot.initRotateMatrix(tmpMat);
	}
}

@:allow(hrt.prefab.fx.EmitterObject)
private class ParticleInstance  {
	public var next : ParticleInstance;

	var emitter : EmitterObject;
	var evaluator : Evaluator;
	var parent : h3d.scene.Object;

	var transform = new ParticleTransform();
	var childTransform = new ParticleTransform();
	public var absPos = new h3d.Matrix();
	public var childMat = new h3d.Matrix();
	public var baseMat : h3d.Matrix;

	public var life = 0.0;
	public var lifeTime = 0.0;
	public var color = new h3d.Vector();
	public var startFrame : Int;
	public var speedAccumulation = new h3d.Vector();

	public var orientation = new h3d.Quat();

	public var def : InstanceDef;

	public function new() {
	}

	public function init(emitter: EmitterObject, def: InstanceDef) {
		transform.reset();
		childTransform.reset();
		life = 0;
		lifeTime = 0;
		startFrame = 0;
		speedAccumulation.set(0,0,0);
		orientation.identity();

		switch(emitter.simulationSpace){
			// Particles in Local are spawned next to emitter in the scene tree,
			// so emitter shape can be transformed (especially scaled) without affecting children
			case Local : transform.parent = emitter.parent;
			case World : transform.parent = emitter.getScene();
		}
		this.def = def;
		this.emitter = emitter;
		this.evaluator = new Evaluator(emitter.random);
		evaluator.vecPool = this.emitter.vecPool;
	}

	public function dispose() {
		transform.parent = childTransform.parent = null;
		emitter = null;
	}

	public function setPosition( x, y, z ) {
		transform.setPosition(x, y, z);
	}

	public function setRotation( quat ) {
		transform.setRotation(quat);
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
	static var tmpPos = new h3d.Vector();
	static var tmpCamRotAxis = new h3d.Vector();
	static var tmpCamAlign = new h3d.Vector();
	static var tmpCamVec = new h3d.Vector();
	static var tmpCamVec2 = new h3d.Vector();
	static var tmpQuat = new h3d.Quat();
	var tmpColor = new h3d.Vector();


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

	public function update( dt : Float ) {

		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);

		if( life == 0 ) {
			// START LOCAL SPEED
			evaluator.getVector(def.startSpeed, 0.0, tmpSpeedAccumulation);
			if(tmpSpeedAccumulation.length() > 0.001)
				tmpSpeedAccumulation.transform3x3(orientation.toMatrix(tmpMat));
			add(speedAccumulation, tmpSpeedAccumulation);
			// START WORLD SPEED
			evaluator.getVector(def.startWorldSpeed, 0.0, tmpSpeedAccumulation);
			if(tmpSpeedAccumulation.length() > 0.001)
				tmpSpeedAccumulation.transform3x3(emitter.invTransform);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		// ACCELERATION
		evaluator.getVector(def.acceleration, t, tmpSpeedAccumulation);
		tmpSpeedAccumulation.scale3(dt);
		if(tmpSpeedAccumulation.length() > 0.001)
			tmpSpeedAccumulation.transform3x3(orientation.toMatrix(tmpMat));
		add(speedAccumulation, tmpSpeedAccumulation);
		// WORLD ACCELERATION
		evaluator.getVector(def.worldAcceleration, t, tmpSpeedAccumulation);
		tmpSpeedAccumulation.scale3(dt);
		if(tmpSpeedAccumulation.length() > 0.001 && emitter.simulationSpace == Local)
			tmpSpeedAccumulation.transform3x3(emitter.invTransform);
		add(speedAccumulation, tmpSpeedAccumulation);
		// SPEED
		evaluator.getVector(def.localSpeed, t, tmpLocalSpeed);
		if(tmpLocalSpeed.length() > 0.001)
			tmpLocalSpeed.transform3x3(orientation.toMatrix(tmpMat));
		// WORLD SPEED
		evaluator.getVector(def.worldSpeed, t, tmpWorldSpeed);
		if(emitter.simulationSpace == Local)
			tmpWorldSpeed.transform3x3(emitter.invTransform);

		tmpSpeed.set(0,0,0);
		add(tmpSpeed, tmpLocalSpeed);
		add(tmpSpeed, tmpWorldSpeed);
		add(tmpSpeed, speedAccumulation);
		transform.x += tmpSpeed.x * dt;
		transform.y += tmpSpeed.y * dt;
		transform.z += tmpSpeed.z * dt;

		// SPEED ORIENTATION
		if(emitter.emitOrientation == Speed && tmpSpeed.lengthSq() > 0.01)
			transform.qRot.initDirection(tmpSpeed);

		// ROTATION
		var rot = evaluator.getVector(def.rotation, t, tmpRot);
		rot.scale3(Math.PI / 180.0);
		var offset = evaluator.getVector(def.localOffset, t, tmpOffset);
		var scaleVec = evaluator.getVector(def.stretch, t, tmpScale);
		scaleVec.scale3(evaluator.getFloat(def.scale, t));

		// TRANSFORM
		childMat.initScale(scaleVec.x, scaleVec.y, scaleVec.z);
		childMat.rotate(rot.x, rot.y, rot.z);
		childMat.translate(offset.x, offset.y, offset.z);
		if( baseMat != null )
			childMat.multiply(baseMat, childMat);
		childTransform.setTransform(childMat);

		// COLOR
		if( def.color != null ) {
			switch( def.color ) {
				case VCurve(a): color.a = evaluator.getFloat(def.color, t);
				default: color.load(evaluator.getVector(def.color, t, tmpColor));
			}
		}

		// ALIGNMENT
		switch( emitter.alignMode ) {
			case Screen:
				tmpMat.load(emitter.getScene().camera.mcam);
				tmpMat.invert();
				switch( emitter.simulationSpace ) {
					case Local: tmpMat.multiply3x4(tmpMat, emitter.invTransform);
					case World:
				}
				tmpMat.prependRotation(0, Math.PI, 0);
				var q = transform.qRot;
				q.initRotateMatrix(tmpMat);
				q.normalize();

				transform.calcAbsPos();
				childTransform.calcAbsPos();
				absPos.multiply(childTransform.absPos, transform.absPos);

			case Axis:
				transform.calcAbsPos();

				var absChildMat = tmpMat;
				absChildMat.multiply3x4(transform.absPos, childMat);
				tmpCamAlign.load(emitter.alignAxis);
				tmpCamAlign.transform3x3(absChildMat);
				tmpCamAlign.normalizeFast();

				tmpCamRotAxis.load(emitter.alignLockAxis);
				tmpCamRotAxis.transform3x3(transform.absPos);
				tmpCamRotAxis.normalizeFast();

				tmpCamVec.load(emitter.getScene().camera.pos);
				sub(tmpCamVec, transform.absPos.getPosition(tmpPos));
				tmpCamVec.normalizeFast();

				tmpCamVec2.load(tmpCamVec);
				tmpCamVec2.scale3(tmpCamVec.dot(tmpCamRotAxis));
				sub(tmpCamVec, tmpCamVec2);
				tmpCamVec.normalizeFast();

				var angle = hxd.Math.acos(tmpCamAlign.dot(tmpCamVec));
				cross(tmpCamAlign, tmpCamVec2);
				if(tmpCamRotAxis.dot(tmpCamAlign) < 0)
					angle = -angle;

				tmpQuat.identity();
				tmpQuat.initRotateAxis(emitter.alignLockAxis.x, emitter.alignLockAxis.y, emitter.alignLockAxis.z, angle);
				var cq = childTransform.qRot;
				cq.multiply(cq, tmpQuat);
				childTransform.setRotation(cq);

				childTransform.calcAbsPos();
				absPos.multiply(childTransform.absPos, transform.absPos);

			case None:
				transform.calcAbsPos();
				childTransform.calcAbsPos();
				absPos.multiply(childTransform.absPos, transform.absPos);
		}

		// COLLISION
		if( emitter.useCollision ) {
			var worldPos = absPos.getPosition(tmpPos);
			if( worldPos.z < 0 ) {
				if( emitter.killOnCollision == 1 || hxd.Math.random() < emitter.killOnCollision ) {
					life = lifeTime + 1; // No survivor
				}
				else {
					var speedAmount = speedAccumulation.length();
					speedAccumulation.normalize();
					var newDir = speedAccumulation.reflect(tmpGroundNormal);
					newDir.scale3(emitter.elasticity);
					newDir.scale3(speedAmount);
					speedAccumulation.set(newDir.x, newDir.y, newDir.z);
					transform.z = 0;
					absPos.multiply(childTransform.absPos, transform.absPos);
				}
			}
		}

		life += dt;
	}
}

@:allow(hrt.prefab.fx.ParticleInstance)
@:allow(hrt.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public static var pool : ParticleInstance;
	public static var poolSize = 0;
	public static function clearPool() {
		pool = null;
		poolSize = 0;
	}

	public var instDef : InstanceDef;

	public var batch : h3d.scene.MeshBatch;
	public var particles : ParticleInstance;
	public var shaderAnims : ShaderAnims;

	public var isSubEmitter : Bool = false;
	public var parentEmitter : EmitterObject = null;
	public var enable : Bool;
	public var particleVisibility(default, null) : Bool;

	public var catchupSpeed = 4; // Use larger ticks when catching-up to save calculations
	public var maxCatchupWindow = 0.5; // How many seconds max to simulate when catching up
	public var totalBurstCount : Int = 0; // Keep track of burst count

	// RANDOM
	public var seedGroup = 0;
	// OBJECTS
	public var particleTemplate : hrt.prefab.Object3D;
	public var subEmitterTemplate : Emitter;
	public var trailTemplate : Trail;
	public var subEmitters : Array<EmitterObject> = [];
	public var trails : Array<EmitterTrail> = [];
	// LIFE
	public var lifeTime = 2.0;
	public var lifeTimeRand = 0.0;
	// EMIT PARAMS
	public var emitOrientation : Orientation = Forward;
	public var simulationSpace : SimulationSpace = Local;
	public var emitType : EmitType = Infinity;
	public var burstCount : Int = 1;
	public var burstParticleCount : Int = 5;
	public var burstDelay : Float = 1.0;
	public var emitDuration : Float = 1.0;
	public var emitRate : Value;
	public var maxCount = 20;
	// EMIT SHAPE
	public var emitShape : EmitShape = Cylinder;
	public var emitAngle : Float = 0.0;
	public var emitRad1 : Float = 1.0;
	public var emitRad2 : Float = 1.0;
	public var emitSurface : Bool = false;
	// ANIMATION
	public var frameCount : Int = 0;
	public var frameDivisionX : Int = 1;
	public var frameDivisionY : Int = 1;
	public var animationRepeat : Float = 1;
	public var animationLoop : Bool = true;
	// ALIGNMENT
	public var alignMode : AlignMode;
	public var alignAxis : h3d.Vector;
	public var alignLockAxis : h3d.Vector;
	// COLLISION
	public var elasticity : Float = 1.0;
	public var killOnCollision : Float = 0.0;
	public var useCollision : Bool = false;

	public var invTransform : h3d.Matrix;

	var random: hxd.Rand;
	var randomSeed = 0;
	var context : hrt.prefab.Context;
	var emitCount = 0;
	var lastTime = -1.0;
	var curTime = 0.0;
	var evaluator : Evaluator;
	var vecPool = new Evaluator.VecPool();
	var numInstances = 0;

	public function new(?parent) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
		evaluator = new Evaluator(random);
		evaluator.vecPool = vecPool;
		invTransform = new h3d.Matrix();
		reset();
	}

	public function reset() {
		particleVisibility = true;
		enable = true;
		random.init(randomSeed);
		curTime = 0.0;
		lastTime = 0.0;
		emitCount = 0;
		totalBurstCount = 0;

		var p = particles;
		while(p != null) {
			var n = p.next;
			disposeInstance(p);
			p = n;
		}
		particles = null;
		for( s in subEmitters ) {
			s.remove();
		}
		subEmitters = [];
		for( t in trails ) {
			t.trail.remove();
		}
		trails = [];
	}

	override function onRemove() {
		super.onRemove();
		reset();
	}

	public function setParticleVibility( b : Bool ){
		particleVisibility = b;
	}

	function allocInstance() {
		++numInstances;
		if(pool != null) {
			var p = pool;
			pool = p.next;
			--poolSize;
			return p;
		}
		var p = new ParticleInstance();
		return p;
	}

	var tmpPos = new h3d.Vector();
	var tmpCtx : hrt.prefab.Context;
	function disposeInstance(p: ParticleInstance) {

		// TRAIL
		for( t in trails ) {
			if( t.particle == p ) {
				t.particle = null;
				break;
			}
		}

		p.next = pool;
		p.dispose();
		pool = p;
		--numInstances;
		++poolSize;
		if(numInstances < 0)
			throw "assert";
	}

	static var tmpQuat = new h3d.Quat();
	static var tmpEmitterQuat = new h3d.Quat();
	static var tmpOffset = new h3d.Vector();
	static var tmpVec = new h3d.Vector();
	static var tmpDir = new h3d.Vector();
	static var tmpScale = new h3d.Vector();
	static var tmpMat = new h3d.Matrix();
	static var tmpMat2 = new h3d.Matrix();
	function doEmit( count : Int ) {
		if( count == 0 )
			return;

		if( instDef == null || particleTemplate == null )
			return;

		var shapeAngle = hxd.Math.degToRad(emitAngle) / 2.0;
		var emitterQuat : h3d.Quat = null;
		var emitterBaseMat : h3d.Matrix = null;

		for( i in 0...count ) {
			var part = allocInstance();
			part.init(this, instDef);
			part.next = particles;
			particles = part;

			if(emitterBaseMat == null) {
				emitterBaseMat = particleTemplate.getTransform();
				part.baseMat = emitterBaseMat;
			}
			else
				part.baseMat = emitterBaseMat.clone();

			part.lifeTime = hxd.Math.max(0.01, lifeTime + hxd.Math.srand(lifeTimeRand));
			tmpQuat.identity();

			switch( emitShape ) {
				case Box:
					tmpOffset.set(random.srand(0.5), random.srand(0.5), random.srand(0.5));
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
					tmpOffset.set(x - 0.5, dx * 0.5, dy * 0.5);
					if( emitOrientation == Normal )
						tmpQuat.initRotation(0, -hxd.Math.atan2(dy, dx), Math.PI/2);
					tmpOffset.y *= hxd.Math.lerp(emitRad1, emitRad2, x);
					tmpOffset.z *= hxd.Math.lerp(emitRad1, emitRad2, x);
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
					part.setRotation(tmpQuat);
					part.orientation.load(tmpQuat);
				case World:
					tmpVec.load(tmpOffset);
					localToGlobal(tmpVec);
					part.setPosition(tmpVec.x, tmpVec.y, tmpVec.z);
					if(emitterQuat == null) {
						emitterQuat = tmpEmitterQuat;
						tmpMat.load(getAbsPos());
						tmpMat.getScale(tmpScale);
						tmpMat.prependScale(1.0/tmpScale.x, 1.0/tmpScale.y, 1.0/tmpScale.z);
						emitterQuat.initRotateMatrix(tmpMat);
						emitterQuat.normalize();
					}
					tmpQuat.multiply(tmpQuat, emitterQuat);
					part.setRotation(tmpQuat);
					part.orientation.load(tmpQuat);
			}

			var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
			part.startFrame = random.random(frameCount);

			if( trailTemplate != null ) {
				if( tmpCtx == null ) {
					tmpCtx = new hrt.prefab.Context();
					tmpCtx.local3d = this.getScene();
					tmpCtx.shared = context.shared;
				}
				tmpCtx.local3d = this.getScene();
				var trail : h3d.scene.Trail = cast trailTemplate.make(tmpCtx).local3d;
				trail.setTransform(part.absPos);
				trails.push({particle: part, trail: trail, timeBeforeDeath: 0.0});
			}
		}
		context.local3d = this;
		emitCount += count;
	}

	function createMeshBatch( startTime : Float ) {

		if( batch != null )
			batch.remove();

		if( particleTemplate == null )
			return;

		var template = particleTemplate.makeInstance(context);
		var mesh = Std.downcast(template.local3d, h3d.scene.Mesh);
		if( mesh == null ) {
			for( i in 0...template.local3d.numChildren ) {
				mesh = Std.downcast(template.local3d.getChildAt(i), h3d.scene.Mesh);
				if( mesh != null ) break;
			}
		}

		if( mesh != null && mesh.primitive != null ) {
			var meshPrim = Std.downcast(mesh.primitive, h3d.prim.MeshPrimitive);

			// Setup mats.
			// Should we do this manually here or make a recursive makeInstance on the template?
			var materials = particleTemplate.getAll(hrt.prefab.Material);
			for(mat in materials) {
				if(mat.enabled)
					mat.makeInstance(template);
			}

			// Setup shaders
			shaderAnims = [];
			var shaders = particleTemplate.getAll(hrt.prefab.Shader);
			for( shader in shaders ) {
				if( !shader.enabled ) continue;
				var shCtx = shader.makeInstance(template);
				if( shCtx == null ) continue;
				hrt.prefab.fx.BaseFX.getShaderAnims(template, shader, shaderAnims);
			}
			for(s in shaderAnims) {
				s.vecPool = vecPool;
			}

			// Animated textures animations
			var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
			if( frameCount > 1 ) {
				if( mesh != null && mesh.material != null && mesh.material.texture != null ) {
					var pshader = new h3d.shader.AnimatedTexture(mesh.material.texture, frameDivisionX, frameDivisionY, frameCount, frameCount * animationRepeat / lifeTime);
					pshader.startTime = startTime;
					pshader.loop = animationLoop;
					mesh.material.mainPass.addShader(pshader);
				}
			}

			if( meshPrim != null ) {
				batch = new h3d.scene.MeshBatch(meshPrim, mesh.material, this);
				batch.name = "batch";
			}
			template.local3d.remove();
		}
	}

	static var camPosTmp : h3d.Vector;
	static var p1PosTmp = new h3d.Vector();
	static var p2PosTmp = new h3d.Vector();
	static function sortZ( p1 : ParticleInstance, p2 : ParticleInstance ) : Int {
		return Std.int(camPosTmp.distanceSq(p2.absPos.getPosition(p1PosTmp)) - camPosTmp.distanceSq(p1.absPos.getPosition(p2PosTmp)));
	}

	function tick( dt : Float, full=true) {

		// Auto remove of sub emitters
		if( !enable && particles == null && isSubEmitter ) {
			parentEmitter.subEmitters.remove(this);
			remove();
			return;
		}

		for( se in subEmitters ) {
			se.tick(dt);
		}

		if( emitRate == null || emitRate == VZero )
			return;

		if( parent != null ) {
			invTransform.load(parent.getAbsPos());
			invTransform.invert();
		}
		vecPool.begin();

		if( enable ) {
			switch emitType {
				case Infinity:
					var emitTarget = evaluator.getSum(emitRate, curTime);
					var delta = hxd.Math.ceil(hxd.Math.min(maxCount - numInstances, emitTarget - emitCount));
					doEmit(delta);
					if( isSubEmitter && (parentEmitter == null || parentEmitter.parent == null) )
						enable = false;
				case Duration:
					var emitTarget = evaluator.getSum(emitRate, hxd.Math.min(curTime, emitDuration));
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

		updateParticles(dt);

		if( full && batch != null ) {
			batch.begin(hxd.Math.nextPOT(maxCount));
			if( particleVisibility ) {
				camPosTmp = getScene().camera.pos;
				particles = haxe.ds.ListSort.sortSingleLinked(particles, sortZ);
				var p = particles;
				var i = 0;
				while(p != null) {
					// Init the color for each particles
					if( p.def.color != null ) {
						switch( p.def.color ) {
							case VCurve(a): batch.material.color.a = p.color.a;
							default: batch.material.color = p.color;
						}
					}
					batch.worldPosition = p.absPos;
					for( anim in shaderAnims ) {
						var t = hxd.Math.clamp(p.life / p.lifeTime, 0.0, 1.0);
						anim.setTime(t);
					}
					// Init the start frame for each particle
					var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
					if( frameCount > 0 && animationRepeat == 0 ) {
						var s = batch.material.mainPass.getShader(h3d.shader.AnimatedTexture);
						if( s != null){
							s.startFrame = p.startFrame;
						}
					}
					batch.emitInstance();
					p = p.next;
					++i;
				}
			}
		}
		lastTime = curTime;
		curTime += dt;
	}

	function updateParticles(dt: Float) {
		var p = particles;
		var prev : ParticleInstance = null;
		while(p != null) {
			var next = p.next;
			if(p.life > lifeTime) {
				if(prev != null)
					prev.next = next;
				else
					particles = next;

				disposeInstance(p);

				// SUB EMITTER
				if( subEmitterTemplate != null ) {
					if( tmpCtx == null ) {
						tmpCtx = new hrt.prefab.Context();
						tmpCtx.local3d = this.getScene();
						tmpCtx.shared = context.shared;
					}
					tmpCtx.local3d = this.getScene();
					var emitter : EmitterObject = cast subEmitterTemplate.makeInstance(tmpCtx).local3d;
					var pos = p.absPos.getPosition(tmpPos);
					emitter.setPosition(pos.x, pos.y, pos.z);
					emitter.isSubEmitter = true;
					emitter.parentEmitter = this;
					subEmitters.push(emitter);
				}
			}
			else {
				p.update(dt);
				prev = p;
			}
			p = next;
		}

		// TRAIL
		var i = 0;
		while( i < trails.length ) {
			var emitterTrail = trails[i];
			var trail = emitterTrail.trail;
			var particle = emitterTrail.particle;
			if( particle != null ) {
				trail.setTransform(particle.absPos);
				i++;
			}
			else {
				emitterTrail.timeBeforeDeath += dt;
				if( emitterTrail.timeBeforeDeath > trail.duration ) {
					trail.remove();
					trails[i] = trails[trails.length - 1];
					trails.pop();
				}
				else
					i++;
			}
		}
	}

	public function setRandSeed(seed: Int) {
		randomSeed = seed ^ seedGroup;
		reset();
	}

	public function setTime(time: Float) {
		if(time < lastTime || lastTime < 0) {
			reset();
		}

		var catchupTime = time - curTime;

		#if !editor
		if(catchupTime > maxCatchupWindow) {
			curTime = time - maxCatchupWindow;
			emitCount = hxd.Math.ceil(evaluator.getSum(emitRate, curTime));
			catchupTime = maxCatchupWindow;
		}
		#end

		var catchupTickRate = hxd.Timer.wantedFPS / catchupSpeed;
		var numTicks = hxd.Math.ceil(catchupTickRate * catchupTime);
		for(i in 0...numTicks) {
			tick(catchupTime / numTicks, i == (numTicks - 1));
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
		// RANDOM
		{ name: "seedGroup", t: PInt(0, 100), def: 0, groupName : "Random"},
		// LIFE
		{ name: "lifeTime", t: PFloat(0, 10), def: 1.0, groupName : "Life" },
		{ name: "lifeTimeRand", t: PFloat(0, 1), def: 0.0, groupName : "Life" },
		// EMIT PARAMS
		{ name: "emitType", t: PEnum(EmitType), def: EmitType.Infinity, disp: "Type", groupName : "Emit Params"  },
		{ name: "emitDuration", t: PFloat(0, 10.0), disp: "Duration", def : 1.0, groupName : "Emit Params" },
		{ name: "emitRate", t: PInt(0, 100), def: 5, disp: "Rate", animate: true, groupName : "Emit Params" },
		{ name: "burstCount", t: PInt(1, 10), disp: "Count", def : 1, groupName : "Emit Params" },
		{ name: "burstDelay", t: PFloat(0, 1.0), disp: "Delay", def : 1.0, groupName : "Emit Params" },
		{ name: "burstParticleCount", t: PInt(1, 10), disp: "Particle Count", def : 1, groupName : "Emit Params" },
		{ name: "simulationSpace", t: PEnum(SimulationSpace), def: SimulationSpace.Local, disp: "Simulation Space", groupName : "Emit Params" },
		{ name: "emitOrientation", t: PEnum(Orientation), def: Orientation.Forward, disp: "Orientation", groupName : "Emit Params" },
		{ name: "maxCount", t: PInt(0, 100), def: 20, groupName : "Emit Params" },
		// EMIT SHAPE
		{ name: "emitShape", t: PEnum(EmitShape), def: EmitShape.Sphere, disp: "Shape", groupName : "Emit Shape" },
		{ name: "emitAngle", t: PFloat(0, 360.0), disp: "Angle", groupName : "Emit Shape" },
		{ name: "emitRad1", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 1", groupName : "Emit Shape" },
		{ name: "emitRad2", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 2", groupName : "Emit Shape" },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface", groupName : "Emit Shape" },
		// ALIGNMENT
		{ name: "alignMode", t: PEnum(AlignMode), def: AlignMode.None, disp: "Mode", groupName : "Alignment" },
		{ name: "alignAxis", t: PVec(3, -1.0, 1.0), def: [0.,0.,0.], disp: "Axis", groupName : "Alignment" },
		{ name: "alignLockAxis", t: PVec(3, -1.0, 1.0), def: [0.,0.,0.], disp: "Lock Axis", groupName : "Alignment" },
		// ANIMATION
		{ name: "frameCount", t: PInt(0), def: 0, groupName : "Animation" },
		{ name: "frameDivisionX", t: PInt(1), def: 1, groupName : "Animation" },
		{ name: "frameDivisionY", t: PInt(1), def: 1, groupName : "Animation" },
		{ name: "animationRepeat", t: PFloat(0, 2.0), def: 1.0, groupName : "Animation" },
		{ name: "animationLoop", t: PBool, def: true, groupName : "Animation" },
		// COLLISION
		{ name: "useCollision", t: PBool, def: false, groupName : "Ground Collision" },
		{ name: "elasticity", t: PFloat(0, 1.0), disp: "Elasticity", def : 1.0, groupName : "Ground Collision" },
		{ name: "killOnCollision", t: PFloat(0, 1.0), disp: "Kill On Collision", def : 0.0, groupName : "Ground Collision" },
	];

	public static var instanceParams : Array<ParamDef> = [
		{ name: "instSpeed",      			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Fixed Speed" },
		{ name: "instWorldSpeed", 			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Fixed World Speed" },
		{ name: "instStartSpeed",      		t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Start Speed" },
		{ name: "instStartWorldSpeed", 		t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Start World Speed" },
		{ name: "instAcceleration",			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Acceleration" },
		{ name: "instWorldAcceleration",	t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "World Acceleration" },
		{ name: "instScale",      			t: PFloat(0, 2.0),    def: 1.,         disp: "Scale" },
		{ name: "instStretch",    			t: PVec(3, 0.0, 2.0), def: [1.,1.,1.], disp: "Stretch" },
		{ name: "instRotation",   			t: PVec(3, 0, 360),   def: [0.,0.,0.], disp: "Rotation" },
		{ name: "instOffset",     			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Offset" }
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
		// Don't make children, which are used to setup particles
		return makeInstance(ctx);
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
		var template : Object3D = cast children.find( c -> c.enabled && (c.name == null || c.name.indexOf("collision") == -1) && c.to(Object3D) != null && c.to(Object3D).visible );

		function makeParam(scope: Prefab, name: String): Value {
			var getCurve = hrt.prefab.Curve.getCurve.bind(scope);
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
			var curves = hrt.prefab.Curve.getCurves(scope, name);
			if(curves == null || curves.length == 0)
				return null;
			return hrt.prefab.Curve.getColorValue(curves);
		}

		if(template != null) {
			emitterObj.instDef = {
				localSpeed: makeParam(this, "instSpeed"),
				worldSpeed: makeParam(this, "instWorldSpeed"),
				startSpeed: makeParam(this, "instStartSpeed"),
				startWorldSpeed: makeParam(this, "instStartWorldSpeed"),
				acceleration: makeParam(this, "instAcceleration"),
				worldAcceleration: makeParam(this, "instWorldAcceleration"),
				localOffset: makeParam(this, "instOffset"),
				scale: makeParam(this, "instScale"),
				stretch: makeParam(this, "instStretch"),
				rotation: makeParam(this, "instRotation"),
				color: makeColor(template, "color"),
			};

			emitterObj.particleTemplate = template;
		}

		// SUB-EMITTER
		var subEmitterTemplate : Emitter = cast children.find( p -> p.enabled && Std.downcast(p, Emitter) != null && p.to(Object3D).visible);
		emitterObj.subEmitterTemplate = subEmitterTemplate;
		// TRAIL
		var trailTemplate : Trail = cast children.find( p -> p.enabled && Std.downcast(p, Trail) != null && p.to(Object3D).visible);
		emitterObj.trailTemplate = trailTemplate;
		// RANDOM
		emitterObj.seedGroup 			= 	getParamVal("seedGroup");
		// LIFE
		emitterObj.lifeTime 			= 	getParamVal("lifeTime");
		emitterObj.lifeTimeRand 		= 	getParamVal("lifeTimeRand");
		// EMIT PARAMS
		emitterObj.emitType 			= 	getParamVal("emitType");
		emitterObj.burstCount 			= 	getParamVal("burstCount");
		emitterObj.burstDelay 			= 	getParamVal("burstDelay");
		emitterObj.burstParticleCount 	= 	getParamVal("burstParticleCount");
		emitterObj.emitDuration 		= 	getParamVal("emitDuration");
		emitterObj.simulationSpace 		= 	getParamVal("simulationSpace");
		emitterObj.emitOrientation 		= 	getParamVal("emitOrientation");
		emitterObj.maxCount 			= 	getParamVal("maxCount");
		emitterObj.emitRate 			= 	makeParam(this, "emitRate");
		emitterObj.emitShape 			= 	getParamVal("emitShape");
		// EMIT SHAPE
		emitterObj.emitAngle 			= 	getParamVal("emitAngle");
		emitterObj.emitRad1 			= 	getParamVal("emitRad1");
		emitterObj.emitRad2 			= 	getParamVal("emitRad2");
		emitterObj.emitSurface 			= 	getParamVal("emitSurface");
		// ALIGNMENT
		emitterObj.alignMode 			= 	getParamVal("alignMode");
		emitterObj.alignAxis 			= 	getParamVal("alignAxis");
		emitterObj.alignLockAxis 		= 	getParamVal("alignLockAxis");
		// ANIMATION
		emitterObj.frameCount 			= 	getParamVal("frameCount");
		emitterObj.frameDivisionX 		= 	getParamVal("frameDivisionX");
		emitterObj.frameDivisionY 		= 	getParamVal("frameDivisionY");
		emitterObj.animationRepeat 		= 	getParamVal("animationRepeat");
		emitterObj.animationLoop 		= 	getParamVal("animationLoop");
		// COLLISION
		emitterObj.useCollision 		= 	getParamVal("useCollision");
		emitterObj.killOnCollision 		= 	getParamVal("killOnCollision");
		emitterObj.elasticity 			= 	getParamVal("elasticity");

		var startTime = 0.0;
		var scene = ctx.local3d.getScene();
		if(scene != null)
			startTime = @:privateAccess scene.renderer.ctx.time;

		emitterObj.createMeshBatch(startTime);

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

			if( pname == "emitShape" || pname == "alignMode" || pname == "useCollision" || pname == "emitType" )
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

		var useCollision = getParamVal("useCollision");
		if( !useCollision ) {
			removeParam("elasticity");
			removeParam("killOnCollision");
		}

		var emitType : EmitType = getParamVal("emitType");
		switch (emitType) {
			case Infinity:
				removeParam("burstCount");
				removeParam("burstDelay");
				removeParam("burstParticleCount");
				removeParam("emitDuration");
			case BurstDuration:
				removeParam("emitRate");
				removeParam("burstCount");
			case Burst:
				removeParam("emitDuration");
				removeParam("emitRate");
			case Duration:
				removeParam("burstCount");
				removeParam("burstDelay");
				removeParam("burstParticleCount");
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
				g.material.mainPass.setPassName("overlay");
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