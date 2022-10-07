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
	orbitSpeed: Value,
	acceleration: Value,
	worldAcceleration: Value,
	localOffset: Value,
	scale: Value,
	stretch: Value,
	rotation: Value
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

	public inline function getPosition() {
		return new h3d.Vector(x, y, z);
	}

	public inline function setPosition( x, y, z ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	public inline function transform3x3( m : h3d.Matrix ) {
		var px = x * m._11 + y * m._21 + z * m._31;
		var py = x * m._12 + y * m._22 + z * m._32;
		var pz = x * m._13 + y * m._23 + z * m._33;
		x = px;
		y = py;
		z = pz;
	}

	public inline function setScale( x, y, z ) {
		this.scaleX = x;
		this.scaleY = y;
		this.scaleZ = z;
	}

	public inline function getWorldPosition() {
		var ppos = parent.getAbsPos();
		return new h3d.Vector(x + ppos.tx, y + ppos.ty, z + ppos.tz);
	}

	public inline function setWorldPosition(v: h3d.Vector) {
		var ppos = parent.getAbsPos();
		x = v.x - ppos.tx;
		y = v.y - ppos.ty;
		z = v.z - ppos.tz;
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
	public function setTransform( mat : h3d.Matrix ) {
		var s = mat.getScale();
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

	var transform = new ParticleTransform();
	var localTransform = new ParticleTransform();
	public var absPos = new h3d.Matrix();
	public var localMat = new h3d.Matrix();
	public var baseMat : h3d.Matrix;

	public var startTime = 0.0;
	public var life = 0.0;
	public var lifeTime = 0.0;
	public var startFrame : Int;
	public var speedAccumulation = new h3d.Vector();
	public var colorMult : h3d.Vector;
	public var distToCam = 0.0;
	public var random : Float;

	public var orientation = new h3d.Quat();

	public var def : InstanceDef;

	public function new() {
	}

	public function init(emitter: EmitterObject, def: InstanceDef) {
		transform.reset();
		localTransform.reset();
		life = 0;
		lifeTime = 0;
		startFrame = 0;
		speedAccumulation.set(0,0,0);
		orientation.identity();
		random = emitter.random.rand();

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
		transform.parent = localTransform.parent = null;
		emitter = null;
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

	public function updateAbsPos() {
		switch( emitter.alignMode ) {
			case Screen|Axis:
				transform.qRot.load(emitter.screenQuat);
			default:
		}

		transform.calcAbsPos();
		localTransform.calcAbsPos();
		absPos.multiply(localTransform.absPos, transform.absPos);
	}

	public function update( dt : Float ) {
		var t = hxd.Math.clamp(life / lifeTime, 0.0, 1.0);
		tmpSpeed.set(0,0,0);

		if( life == 0 ) {
			// START LOCAL SPEED
			evaluator.getVector(def.startSpeed, 0.0, tmpSpeedAccumulation);
			tmpSpeedAccumulation.transform3x3(orientation.toMatrix(tmpMat));
			add(speedAccumulation, tmpSpeedAccumulation);
			// START WORLD SPEED
			evaluator.getVector(def.startWorldSpeed, 0.0, tmpSpeedAccumulation);
			tmpSpeedAccumulation.transform3x3(emitter.invTransform);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		// ACCELERATION
		if(def.acceleration != VZero) {
			evaluator.getVector(def.acceleration, t, tmpSpeedAccumulation);
			tmpSpeedAccumulation.scale3(dt);
			tmpSpeedAccumulation.transform3x3(orientation.toMatrix(tmpMat));
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		// WORLD ACCELERATION
		if(def.worldAcceleration != VZero) {
			evaluator.getVector(def.worldAcceleration, t, tmpSpeedAccumulation);
			tmpSpeedAccumulation.scale3(dt);
			if(emitter.simulationSpace == Local)
				tmpSpeedAccumulation.transform3x3(emitter.invTransform);
			add(speedAccumulation, tmpSpeedAccumulation);
		}

		add(tmpSpeed, speedAccumulation);

		// SPEED
		if(def.localSpeed != VZero) {
			evaluator.getVector(def.localSpeed, t, tmpLocalSpeed);
			tmpLocalSpeed.transform3x3(orientation.toMatrix(tmpMat));
			add(tmpSpeed, tmpLocalSpeed);
		}
		// WORLD SPEED
		if(def.worldSpeed != VZero) {
			evaluator.getVector(def.worldSpeed, t, tmpWorldSpeed);
			if(emitter.simulationSpace == Local)
				tmpWorldSpeed.transform3x3(emitter.invTransform);
			add(tmpSpeed, tmpWorldSpeed);
		}

		if(emitter.simulationSpace == World) {
			tmpSpeed.x *= emitter.worldScale.x;
			tmpSpeed.y *= emitter.worldScale.y;
			tmpSpeed.z *= emitter.worldScale.z;
		}

		transform.x += tmpSpeed.x * dt;
		transform.y += tmpSpeed.y * dt;
		transform.z += tmpSpeed.z * dt;

		if(def.orbitSpeed != VZero) {
			evaluator.getVector(def.orbitSpeed, t, tmpLocalSpeed);
			tmpMat.initRotation(tmpLocalSpeed.x * dt, tmpLocalSpeed.y * dt, tmpLocalSpeed.z * dt);
			// Rotate in emitter space and convert back to world space
			var pos = transform.getWorldPosition();
			var prevPos = transform.getPosition();
			pos.transform3x4(emitter.getInvPos());
			pos.transform3x3(tmpMat);
			pos.transform3x4(emitter.getAbsPos());
			transform.setWorldPosition(pos);

			// Take transform into account into local speed
			var delta = transform.getPosition().sub(prevPos);
			delta.scale(1 / dt);
			add(tmpSpeed, delta);
		}

		// SPEED ORIENTATION
		if(emitter.emitOrientation == Speed && tmpSpeed.lengthSq() > 0.01)
			transform.qRot.initDirection(tmpSpeed);

		// ROTATION
		var rot = evaluator.getVector(def.rotation, t, tmpRot);
		rot.scale3(Math.PI / 180.0);

		//OFFSET
		var offset = evaluator.getVector(def.localOffset, t, tmpOffset);

		//SCALE
		var scaleVec = evaluator.getVector(def.stretch, t, tmpScale);
		scaleVec.scale3(evaluator.getFloat(def.scale, t));

		// TRANSFORM
		localMat.initScale(scaleVec.x, scaleVec.y, scaleVec.z);
		localMat.rotate(rot.x, rot.y, rot.z);
		localMat.translate(offset.x, offset.y, offset.z);
		if( baseMat != null )
			localMat.multiply(baseMat, localMat);
		localTransform.setTransform(localMat);

		updateAbsPos();

		// COLLISION
		if( emitter.useCollision ) {
			var worldPos = absPos.getPosition();
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
					absPos.multiply(localTransform.absPos, transform.absPos);
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

	public var startTime = 0.0;
	public var catchupSpeed = 4; // Use larger ticks when catching-up to save calculations
	public var totalBurstCount : Int = 0; // Keep track of burst count
	#if !editor
	public var maxCatchupWindow = 0.5; // How many seconds max to simulate when catching up
	#end

	// RANDOM
	public var seedGroup = 0;
	// OBJECTS
	public var particleTemplate : hrt.prefab.Object3D;
	public var subEmitterTemplate : Emitter;
	public var trailTemplate : hrt.prefab.l3d.Trail;
	public var subEmitters : Array<EmitterObject> = [];
	public var trails : Array<EmitterTrail> = [];
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
	var vecPool = new Evaluator.VecPool();
	var numInstances = 0;
	var baseEmitterShader : hrt.shader.BaseEmitter = null;
	var animatedTextureShader : h3d.shader.AnimatedTexture = null;
	var colorMultShader : h3d.shader.ColorMult = null;

	public function new(?parent) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
		evaluator = new Evaluator(random);
		evaluator.vecPool = vecPool;
		reset();
	}

	public function reset() {
		enable = true;
		random.init(randomSeed);
		curTime = 0.0;
		emitCount = 0;
		emitTarget = 0;
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
	static var tmpVec2 = new h3d.Vector();
	static var tmpDir = new h3d.Vector();
	static var tmpScale = new h3d.Vector();
	static var tmpMat = new h3d.Matrix();
	static var tmpMat2 = new h3d.Matrix();
	static var tmpPt = new h3d.col.Point();
	function doEmit( count : Int ) {
		if( count == 0 )
			return;

		if( instDef == null || particleTemplate == null )
			return;

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

			part.startTime = startTime + curTime;
			part.lifeTime = hxd.Math.max(0.01, lifeTime + random.srand(lifeTimeRand));

			if(useRandomColor) {
				if (useRandomGradient) {
					part.colorMult = Gradient.evalData(randomGradient, random.rand());
				}
				else {
					var col = new h3d.Vector();
					col.lerp(randomColor1, randomColor2, random.rand());
					part.colorMult = col;
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
					part.transform.setPosition(tmpOffset.x, tmpOffset.y, tmpOffset.z);
					tmpQuat.multiply(emitterQuat, tmpQuat);
					part.transform.setRotation(tmpQuat);
					part.orientation.load(tmpQuat);
				case World:
					tmpPt.set(tmpOffset.x, tmpOffset.y, tmpOffset.z);
					localToGlobal(tmpPt);
					part.transform.setPosition(tmpPt.x, tmpPt.y, tmpPt.z);
					emitterQuat = tmpEmitterQuat;
					tmpMat.load(getAbsPos());
					var s = tmpMat.getScale();
					tmpMat.prependScale(1.0/s.x, 1.0/s.y, 1.0/s.z);
					emitterQuat.initRotateMatrix(tmpMat);
					emitterQuat.normalize();
					tmpQuat.multiply(tmpQuat, emitterQuat);
					part.transform.setRotation(tmpQuat);
					part.orientation.load(tmpQuat);
					part.transform.setScale(worldScale.x, worldScale.y, worldScale.z);
			}

			var frameCount = frameCount == 0 ? frameDivisionX * frameDivisionY : frameCount;
			if(animationLoop)
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

	function createMeshBatch() {

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
			if( frameCount > 1 && spriteSheet != null ) {
				var tex = hxd.res.Loader.currentInstance.load(spriteSheet).toTexture();
				animatedTextureShader = new h3d.shader.AnimatedTexture(tex, frameDivisionX, frameDivisionY, frameCount, frameCount * animationSpeed / lifeTime);
				animatedTextureShader.startTime = startTime;
				animatedTextureShader.loop = animationLoop;
				animatedTextureShader.setPriority(1);
				mesh.material.mainPass.addShader(animatedTextureShader);
			}

			baseEmitterShader = new hrt.shader.BaseEmitter();
			mesh.material.mainPass.addShader(baseEmitterShader);

			if(useRandomColor) {
				colorMultShader = new h3d.shader.ColorMult();
				mesh.material.mainPass.addShader(colorMultShader);
			}

			if( meshPrim != null ) {
				batch = new h3d.scene.MeshBatch(meshPrim, mesh.material, this);
				batch.name = "batch";
			}

			/*trace("Shaders for " + this.name);
			@:privateAccess var shaderEntry = mesh.material.mainPass.shaders;
			while(shaderEntry != null) {
				trace(shaderEntry.s);
				shaderEntry = shaderEntry.next;
			}*/

			template.local3d.remove();
		}
	}

	static function sortZ( p1 : ParticleInstance, p2 : ParticleInstance ) : Int {
		return p1.distToCam < p2.distToCam ? 1 : -1;
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

		for( se in subEmitters ) {
			se.tick(dt);
		}

		if( emitRate == null || emitRate == VZero )
			return;

		if( parent != null ) {
			worldScale.load(parent.getAbsPos().getScale());
			invTransform.load(parent.getInvPos());
		}

		vecPool.begin();

		if( enable ) {
			switch emitType {
				case Infinity:
					emitTarget += evaluator.getFloat(emitRate, curTime) * dt;
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

		updateParticles(dt);

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

	function updateMeshBatch() {
		if(batch == null) return;
		batch.begin(hxd.Math.nextPOT(maxCount));
		particles = haxe.ds.ListSort.sortSingleLinked(particles, sortZ);
		var p = particles;
		var i = 0;
		while(p != null) {
			batch.worldPosition = p.absPos;
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
				colorMultShader.color = p.colorMult;
			batch.emitInstance();
			p = p.next;
			++i;
		}
	}

	function updateParticles(dt: Float) {
		var p = particles;
		var prev : ParticleInstance = null;
		var camPos = getScene().camera.pos;
		while(p != null) {
			var next = p.next;
			if(p.life > p.lifeTime) {
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
					var pos = p.absPos.getPosition();
					emitter.setPosition(pos.x, pos.y, pos.z);
					emitter.isSubEmitter = true;
					emitter.parentEmitter = this;
					subEmitters.push(emitter);
				}
			}
			else {
				p.update(dt);
				if(p.distToCam < 0 || enableSort) {
					p.distToCam = camPos.distanceSq(p.absPos.getPosition());
				}
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
		time = time * speedFactor + warmUpTime;
		if(hxd.Math.abs(time - curTime) < 1e-6) {  // Time imprecisions can occur during accumulation
			updateAlignment();
			var p = particles;
			while(p != null) {
				p.updateAbsPos();
				p = p.next;
			}
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
			var p = particles;
			while(p != null) {
				p.distToCam = -1;
				p = p.next;
			}
		}
		#end

		var catchupTickRate = hxd.Timer.wantedFPS * speedFactor / catchupSpeed;
		var numTicks = hxd.Math.ceil(catchupTickRate * catchupTime);
		for(i in 0...numTicks)
			tick(catchupTime / numTicks, i == (numTicks - 1));
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
		// RANDOM
		{ name: "seedGroup", t: PInt(0, 100), def: 0, groupName : "Random", disp: "Seed"},
		// LIFE
		{ name: "lifeTime", t: PFloat(0, 10), def: 1.0, groupName : "Time" },
		{ name: "lifeTimeRand", t: PFloat(0, 1), def: 0.0, groupName : "Time" },
		{ name: "speedFactor", disp: "Speed Factor", t: PFloat(0, 1), def: 1.0, groupName : "Time" },
		{ name: "warmUpTime", disp: "Warm Up", t: PFloat(0, 1), def: 0.0, groupName : "Time" },
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
		{ name: "enableSort", t: PBool, def: true, disp: "Enable Sort", groupName : "Emit Params" },
		// EMIT SHAPE
		{ name: "emitShape", t: PEnum(EmitShape), def: EmitShape.Sphere, disp: "Shape", groupName : "Emit Shape" },
		{ name: "emitAngle", t: PFloat(0, 360.0), def: 360.0, disp: "Angle", groupName : "Emit Shape" },
		{ name: "emitRad1", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 1", groupName : "Emit Shape" },
		{ name: "emitRad2", t: PFloat(0, 1.0), def: 1.0, disp: "Radius 2", groupName : "Emit Shape" },
		{ name: "emitSurface", t: PBool, def: false, disp: "Surface", groupName : "Emit Shape" },
		// ALIGNMENT
		{ name: "alignMode", t: PEnum(AlignMode), def: AlignMode.None, disp: "Mode", groupName : "Alignment" },
		{ name: "alignLockAxis", t: PEnum(AlignLockAxis), def: AlignLockAxis.ScreenZ, disp: "Lock Axis", groupName : "Alignment" },
		// COLOR
		{ name: "useRandomColor", t: PBool, def: false, disp: "Random Color", groupName : "Color" },
		{ name: "useRandomGradient", t: PBool, def: false, disp: "Random Gradient", groupName : "Color" },
		{ name: "randomColor1", t: PVec(4), disp: "Color 1", def : [0,0,0,1], groupName : "Color" },
		{ name: "randomColor2", t: PVec(4), disp: "Color 2", def : [1,1,1,1], groupName : "Color" },
		{ name: "randomGradient", t:PGradient, disp: "Gradient", def: Gradient.getDefaultGradientData(), groupName : "Color" },
		// ANIMATION
		{ name: "spriteSheet", t: PFile(["jpg","png"]), def: null, groupName : "Animation", disp: "Sheet" },
		{ name: "frameCount", t: PInt(0), def: 0, groupName : "Animation", disp: "Frames" },
		{ name: "frameDivisionX", t: PInt(1), def: 1, groupName : "Animation", disp: "Divisions X" },
		{ name: "frameDivisionY", t: PInt(1), def: 1, groupName : "Animation", disp: "Divisions Y" },
		{ name: "animationSpeed", t: PFloat(0, 2.0), def: 1.0, groupName : "Animation", disp: "Speed" },
		{ name: "animationLoop", t: PBool, def: true, groupName : "Animation", disp: "Loop" },
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
		{ name: "instOrbitSpeed", 			t: PVec(3, -10, 10),  def: [0.,0.,0.], disp: "Orbit Speed" },
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
		if( ctx == null ) {
			ctx = new Context();
			ctx.init();
		}
		ctx = makeInstance(ctx);
		return ctx;
	}

	function refreshChildren(ctx: Context) {
		// Don't make all children, which are used to setup particles
		for( c in children ) {
			var shader = Std.downcast(c, hrt.prefab.Shader);
			if( shader != null )
				makeChild(ctx, shader);
		}
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

		if(template != null) {
			emitterObj.instDef = {
				localSpeed: makeParam(this, "instSpeed"),
				worldSpeed: makeParam(this, "instWorldSpeed"),
				startSpeed: makeParam(this, "instStartSpeed"),
				startWorldSpeed: makeParam(this, "instStartWorldSpeed"),
				orbitSpeed: makeParam(this, "instOrbitSpeed"),
				acceleration: makeParam(this, "instAcceleration"),
				worldAcceleration: makeParam(this, "instWorldAcceleration"),
				localOffset: makeParam(this, "instOffset"),
				scale: makeParam(this, "instScale"),
				stretch: makeParam(this, "instStretch"),
				rotation: makeParam(this, "instRotation")
			};

			emitterObj.particleTemplate = template;
		}

		// SUB-EMITTER
		var subEmitterTemplate : Emitter = cast children.find( p -> p.enabled && Std.downcast(p, Emitter) != null && p.to(Object3D).visible);
		emitterObj.subEmitterTemplate = subEmitterTemplate;
		// TRAIL
		var trailTemplate : hrt.prefab.l3d.Trail = cast children.find( p -> p.enabled && Std.isOfType(p, hrt.prefab.l3d.Trail) && p.to(Object3D).visible);
		emitterObj.trailTemplate = trailTemplate;
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

		emitterObj.createMeshBatch();
		emitterObj.reset();
		refreshChildren(ctx);

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