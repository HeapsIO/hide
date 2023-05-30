package hrt.prefab.fx;
using Lambda;

class PerObjectRandom extends hxsl.Shader {
	static var SRC = {
		@perInstance @param var randomParam : Float;
		var random : Float;

		function vertex() {
			random = randomParam;
		}
	}
}

class SwarmElement {
	public function new() {};

	public var x: Float = 0.0;
	public var y: Float = 0.0;
	public var z: Float = 0.0;

	public var vx: Float = 0.0;
	public var vy: Float = 0.0;
	public var vz: Float = 0.0;

	// Interpolation
	public var prev_x: Float = 0.0;
	public var prev_y: Float = 0.0;
	public var prev_z: Float = 0.0;

	public var prev_vx: Float = 0.0;
	public var prev_vy: Float = 0.0;
	public var prev_vz: Float = 0.0;
}

class SwarmObject extends h3d.scene.Object {
	public var prefab : Swarm = null;
	public var elements: Array<SwarmElement> = [];
	public var lastPos :h3d.Vector = null;
	public var facingAngle: Float = 0.0;
	public var targetAngle: Float = 0.0;

	public var batch : h3d.scene.MeshBatch = null;
	public var context : Context = null;

	public var swarmElementTemplate: Object3D = null;

	public var shaderAnims : Array<hrt.prefab.fx.BaseFX.ShaderAnimation>;

	public var shader : PerObjectRandom;


	var time = 0.0;
	var stepTime = 0.0;

	#if editor
	public var debugViz : h3d.scene.Graphics = null;

	#end

	public function new( ?parent : h3d.scene.Object, prefab : Swarm) {
		super(parent);
		this.prefab = prefab;
		this.followPositionOnly = true;

		#if editor
		debugViz = new h3d.scene.Graphics(this);
		#end
	}

	public function init() {

		var meshPrimitive : h3d.prim.MeshPrimitive = null;
		var meshMaterial : h3d.mat.Material = null;

		if( batch != null ) {
			batch.remove();
		}

		if (swarmElementTemplate != null) {
			// baseEmitMat = swarmElementTemplate.getTransform();
			// if(baseEmitMat.isIdentityEpsilon(0.01))
			// 	baseEmitMat = null;

			var template = swarmElementTemplate.makeInstance(context);
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

			template.shared.contexts.remove(swarmElementTemplate);
			template.local3d.remove();
			template.local3d = null;
		}

		if (meshPrimitive == null) {
			var cube =  new h3d.prim.Cube(0.25,0.125,0.125, true);
			cube.addUVs();
			cube.addNormals();
			meshPrimitive = cube;
		}

		if (meshPrimitive != null) {
			batch = new h3d.scene.MeshBatch(meshPrimitive, meshMaterial, null);

			shader = new PerObjectRandom();
			batch.material.mainPass.addShader(shader);

			addChildAt(batch, 0);
			batch.name = "emitter";
			batch.calcBounds = true;

			var batchContext = context.clone(null);
			batchContext.local3d = batch;
			// Setup mats.
			// Should we do this manually here or make a recursive makeInstance on the template?
			var materials = prefab.getAll(hrt.prefab.Material);
			for(mat in materials) {

				// Remove materials that are not directly parented to this Swarm
				var p = mat.parent;
				while (p != null && Std.downcast(p, Swarm) == null) {
					p = p.parent;
				}

				if (this.prefab == p) {
					if(mat.enabled) {
						var ctx = mat.makeInstance(batchContext);
						ctx.local3d = null;
					}
				}
			}

			// Setup shaders
			shaderAnims = [];
			var shaders = prefab.getAll(hrt.prefab.Shader);
			for( shader in shaders ) {
				// Remove shaders that are not directly parented to this Swarm
				var p = shader.parent;
				while (p != null && Std.downcast(p, Swarm) == null) {
					p = p.parent;
				}
				if (this.prefab == p) {
					if( !shader.enabled ) continue;
					var shCtx = makeShaderInstance(shader, batchContext);
					if( shCtx == null ) continue;

					shCtx.local3d = null; // Prevent shader.iterMaterials from adding our objet to the list incorectly

					hrt.prefab.fx.BaseFX.getShaderAnims(shCtx, shader, shaderAnims, batch);
				}
			}

			// Pre-heat the swarm system
			stepTime = 2.0 * stepSize + hxd.Math.EPSILON;
			//updateMeshBatch();
		}

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

	static var tmpVector = new h3d.Vector();
	static var tmpVector2 = new h3d.Vector();
	static var tmpVector3 = new h3d.Vector();
	static var tmpQuat = new h3d.Quat();

	var stepSize = 1.0/15.0;
	var maxIter = 3;

	// Performs a fixed step in the simulation
	// Avoid degenerating parameters at low framerates
	function step() {
		var absPos = getAbsPos();

		if (lastPos == null) {
			lastPos = absPos.getPosition();
		}

		var curPos = absPos.getPosition();

		if (prefab.autoTrackRotation) {
			var delta = curPos.sub(lastPos);
			delta.z = 0.0;

			if (delta.lengthSq() > 0.00001) {
				delta.normalize();
				var forward = tmpVector;
				forward.set(1.0,0.0,0.0);
				var up = tmpVector2;
				up.set(0.0,0.0,1.0);

				targetAngle = -hxd.Math.atan2(delta.cross(forward).dot(up), delta.dot(forward));
			}

			if (stepSize > 0.0001) {
				var diff = (targetAngle - facingAngle);
				while (diff > hxd.Math.PI) {
					diff -= hxd.Math.PI * 2.0;
				}
				while (diff < -hxd.Math.PI) {
					diff += hxd.Math.PI * 2.0;
				}
				facingAngle += diff * (1-hxd.Math.pow(1-prefab.trackRotationSpeed, stepSize));
				facingAngle = (facingAngle % (hxd.Math.PI * 2.0));
			}
		}


		lastPos.load(curPos);

		var prevLen = elements.length;
		elements.resize(prefab.numObjects);
		for (i in prevLen...prefab.numObjects) {
			var pos = getPointPos(i, tmpVector);
			pos.transform(absPos);
			var e = new SwarmElement();
			e.x = pos.x;
			e.y = pos.y;
			e.z = pos.z;

			e.prev_vx = e.x;
			e.prev_vy = e.y;
			e.prev_vz = e.z;

			elements[i] = e;
		}


		for (i in 0...elements.length) {
			var e = elements[i];


			var target = getPointPos(i, tmpVector);

			if (hxd.Math.isNaN(e.x) ||
				hxd.Math.isNaN(e.y) ||
				hxd.Math.isNaN(e.z) ||
				hxd.Math.isNaN(e.vx) ||
				hxd.Math.isNaN(e.vy) ||
				hxd.Math.isNaN(e.vz)
				)
			{
				e.x = target.x;
				e.y = target.y;
				e.z = target.z;

				e.vx = 0.0;
				e.vy = 0.0;
				e.vz = 0.0;
			}

			target.transform(absPos);
			var dir = tmpVector2;
			dir.set(target.x - e.x, target.y - e.y, target.z - e.z);
			var len = dir.length();

			e.prev_vx = e.vx;
			e.prev_vy = e.vy;
			e.prev_vz = e.vz;

			e.prev_x = e.x;
			e.prev_y = e.y;
			e.prev_z = e.z;

			if (len > 0.001) {
				var curVec = tmpVector3;
				curVec.set(e.vx, e.vy, e.vz);
				dir.normalize();

				var randAccelMult = Math.exp((hashf(i, 456317) - 0.5) * prefab.accelerationRandom);
				var noiseAccelMult = prefab.accelerationNoise != 0 ? Math.exp(noise(i) * prefab.accelerationNoise) : 1.0;
				dir.scale(len * prefab.acceleration * randAccelMult * noiseAccelMult);
				curVec.scale(prefab.braking);
				dir = dir.sub(curVec);

				e.vx += dir.x * stepSize;
				e.vy += dir.y * stepSize;
				e.vz += dir.z * stepSize;

				curVec.set(e.vx, e.vy, e.vz);
				var spd = curVec.length();
				var randMaxSpeedMult = Math.exp((hashf(i, 11427) - 0.5) * prefab.maxSpeedRandom);
				var noiseMaxSpeedMult = prefab.maxSpeedNoise != 0 ? Math.exp(noise(i+7) * prefab.maxSpeedNoise) : 1.0;

				spd = hxd.Math.clamp(spd, 0.0, prefab.maxSpeed * randMaxSpeedMult * noiseMaxSpeedMult);
				curVec.normalize();

				var spdNorm = tmpVector2;
				spdNorm.load(curVec);
				spdNorm.set(spdNorm.y, -spdNorm.x, spdNorm.z);

				spdNorm.scale(hxd.Math.sin(time * prefab.objectSelfSinFreq + hashf(i, 17) * hxd.Math.PI * 2.0) * prefab.objectSelfSin * hxd.Math.max(0.10, spd/prefab.maxSpeed));

				curVec.scale(spd);

				e.vx = curVec.x;
				e.vy = curVec.y;
				e.vz = curVec.z;

				e.x += e.vx * stepSize + spdNorm.x * stepSize;
				e.y += e.vy * stepSize + spdNorm.y * stepSize;
				e.z += e.vz * stepSize + spdNorm.z * stepSize;
			}
		}

		#if debug
		debugViz.clear();
		if (prefab.debugTargets) {
			for (i in 0...prefab.numObjects) {
				debugViz.setColorF(0.0,1.0,1.0,1.0);
				drawPoint(debugViz, getPointPos(i, tmpVector));
			}
		}
		#end
	}

	override function syncRec(ctx:h3d.scene.RenderContext) {
		super.syncRec(ctx);

		stepTime += ctx.elapsedTime;
		time += stepTime;

		var numIter = 0;
		while(stepTime > stepSize && numIter < maxIter) {
			stepTime -= stepSize;
			numIter += 1;

			step();
		}

		stepTime = stepTime % stepSize;

		updateMeshBatch();
	}

	function updateMeshBatch() {
		if(batch == null) return;

		var parentScale = tmpVector3;
		if (parent != null) {
			parentScale.load(parent.getAbsPos().getScale());
		} else {
			parentScale.set(1.0,1.0,1.0);
		}
		batch.begin(hxd.Math.nextPOT(prefab.numObjects));

		for (i => e in elements) {
			var dd = stepTime/stepSize;

			var x = hxd.Math.lerp(e.prev_x, e.x, dd);
			var y = hxd.Math.lerp(e.prev_y, e.y, dd);
			var z = hxd.Math.lerp(e.prev_z, e.z, dd);

			var vx = hxd.Math.lerp(e.prev_vx, e.vx, dd);
			var vy = hxd.Math.lerp(e.prev_vy, e.vy, dd);
			var vz = hxd.Math.lerp(e.prev_vz, e.vz, dd);

			tmpVector.set(vx, vy, vz);
			if (tmpVector.lengthSq() < hxd.Math.EPSILON ) {
				tmpVector.set(1.0,0,0);
			}
			var quat = tmpQuat;
			quat.initDirection(tmpVector);

			if (batch.worldPosition == null)
				batch.worldPosition = new h3d.Matrix();

			quat.toMatrix(batch.worldPosition);

			batch.worldPosition.scale(parentScale.x, parentScale.y, parentScale.z);

			batch.worldPosition.tx = x;
			batch.worldPosition.ty = y;
			batch.worldPosition.tz = z;
			batch.worldPosition._44 = 1.0;


			shader.randomParam = hashf(i, 77894 + prefab.seed);
			batch.emitInstance();
		}

	}

	#if editor
	function drawPoint(viz: h3d.scene.Graphics, pos: h3d.Vector, size: Float = 0.5) {
		viz.moveTo(pos.x - size/2.0, pos.y, pos.z);
		viz.lineTo(pos.x + size/2.0, pos.y, pos.z);

		viz.moveTo(pos.x, pos.y - size/2.0, pos.z);
		viz.lineTo(pos.x, pos.y + size/2.0, pos.z);

		viz.moveTo(pos.x, pos.y, pos.z - size/2.0);
		viz.lineTo(pos.x, pos.y, pos.z + size/2.0);
	}
	#end

	inline function noise(id: Int) : Float {
		var h = hashf(id, 7841);
		return hxd.Math.sin(h * time * prefab.noiseSpeed / 24.0 + hxd.Math.sin(h/13.47 * time * prefab.noiseSpeed));
	}

	inline function hashf(id: Int, seed:Int) : Float {
		var h = hxd.Rand.hash(id, seed);
		return (h % 10007) / 10007.0;
	}

	function getPointPos(id: Int, ?outPos: h3d.Vector) : h3d.Vector {
		if (outPos == null)
			outPos = new h3d.Vector();

		var s = prefab.seed;

		var r = hxd.Math.lerp(0.5, 1.5, hashf(id, 188947+s)) * 1.0;
		var theta = hxd.Math.lerp(0.2, hxd.Math.PI * 2.0 - 0.2, hashf(id, 7841+s) % 1.0);
		var sigma = (hashf(id, 4449) % 1.0 + prefab.baseTargetRotationSpeed * time * hxd.Math.lerp(0.5, 1.5, hashf(id, 99741+s)) * 0.05) * hxd.Math.PI * 2.0 + facingAngle;

		var st = hxd.Math.sin(theta);
		outPos.x = r * st * hxd.Math.cos(sigma);
		outPos.y = r * st * hxd.Math.sin(sigma);
		outPos.z = r * hxd.Math.cos(theta);

		return outPos;
	}

}

class Swarm extends Object3D {
	@:s public var numObjects : Int = 3;
	@:s public var seed : Int = 0;
	@:s public var acceleration : Float = 5.0;
	@:s public var accelerationRandom : Float = 0.0;
	@:s public var accelerationNoise : Float = 0.0;

	@:s public var maxSpeed : Float = 10.0;
	@:s public var maxSpeedRandom : Float = 0.0;
	@:s public var maxSpeedNoise : Float = 0.0;

	@:s public var braking : Float = 5.0;

	@:s public var baseTargetRotationSpeed: Float = 1.0;
	@:s public var baseTargetRotationSpeedSpread : Float = 0.0;

	@:s public var objectSelfSin : Float = 0.0;
	@:s public var objectSelfSinFreq : Float = 0.0;

	@:s public var autoTrackRotation : Bool = false;
	@:s public var trackRotationSpeed : Float = 0.5;

	@:s public var noiseSpeed : Float = 1.0;




	@:s public var debugTargets : Bool = false;

	// Override child creation
	override function make(ctx: Context) {
		if( ctx == null ) {
			ctx = new Context();
			ctx.init();
		}
		ctx = makeInstance(ctx);
		return ctx;
	}

	override function createObject(ctx:Context) {
		var obj = new SwarmObject(ctx.local3d, this);
		obj.context = ctx;
		return obj;
	}

	override function updateInstance( ctx: Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		var swarm : SwarmObject = cast ctx.local3d;

		var template : Object3D = cast children.find(
			c -> c.enabled &&
			(c.name == null || c.name.indexOf("collision") == -1) &&
			c.to(Object3D) != null &&
			c.to(Object3D).visible);

		swarm.swarmElementTemplate = template;

		swarm.init();
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "random", name : "Swarm" };
	}

	override public function edit(ctx:EditContext) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Swarm Entities">
			<dl>
				<dt title="Totla number of entities in the swarm">Count</dt><dd><input type="range" field="numObjects" min="1" max="100" step="1"/></dd>
				<dt title="Randomize the values of the swarm">Random Seed</dt><dd><input type="number" field="seed"/></dd>
				<dt title="The acceleration of an entity">Acceleration</dt><dd><input type="range" field="acceleration" min = "0.01" max = "10.0"/></dd>
				<dt title="Randomly multiply the acceleration of each entity. A value ">Rand Acceleration</dt><dd><input type="range" field="accelerationRandom" min = "0.00" max = "1.0"/></dd>
				<dt title="Add a noise to the acceleration">Noise Acceleration</dt><dd><input type="range" field="accelerationNoise" min = "0.0" max = "1.0"/></dd>



				<dt title="The maximum speed at witch a entity can move">MaxSpeed</dt><dd><input type="range" field="maxSpeed" min = "0.01" max = "100.0"/></dd>
				<dt title="Randomly multiply the max speed of each entity">Rand MaxSpeed</dt><dd><input type="range" field="maxSpeedRandom" min = "0.00" max = "1.0"/></dd>
				<dt title="Add a noise to the max speed">Noise MaxSpeed</dt><dd><input type="range" field="maxSpeedNoise" min = "0.0" max = "1.0"/></dd>



				<dt title="How much the entity brakes when approaching the target">Braking</dt><dd><input type="range" field="braking" min = "0.01" max = "10.0"/></dd>

				<dt title="Add a sinusoid to the entities movement that scales with the current speed of the entity">Move Sin Amp.</dt><dd><input type="range" field="objectSelfSin" min = "0.01" max = "10.0"/></dd>
				<dt title="The frequency of the sinusoid that\' added to the movement">Move Sin Freq</dt><dd><input type="range" field="objectSelfSinFreq" min = "0.01" max = "10.0"/></dd>


			</dl>
		</div>

		<div class="group" name="Targets">
		<dl>
			<details><summary> info </summary><p>Controls the targets that the entities follow. Each entity has a fixed target that it will try to reach. Use theses settings to add some movement to the targets to randomise the placement of the entities.</details>

			<dt title="Add a rotation to the targets that helps randomize the spread of the entities">Auto Rot.</dt><dd><input type="range" field="baseTargetRotationSpeed" min = "-10.0" max = "10.0"/></dd>

			<dt title="Align the targets with the velocity of the swarm target object">Align Vel.</dt><dd><input type="checkbox" field="autoTrackRotation"/></dd>
			<dt title="At which speed the targets realign themselves">Align Vel. Spd.</dt><dd><input type="range" field="trackRotationSpeed" min = "0.01" max = "1.0"/></dd>

			<dt title="Displays the current position of the targets (editor only)">View Targets</dt><dd><input type="checkbox" field="debugTargets"/></dd>
		</dl>
		</div>

		<div class="group" name="Advanced">
		<dl>
			<dt title="Add a rotation to the targets that helps randomize the spread of the entities">Noise Speed</dt><dd><input type="range" field="noiseSpeed" min = "0.01" max = "10.0"/></dd>
		</dl>
		</div>
		'
		), this);
	}
	#end

	static var _ = hrt.prefab.Library.register("Swarm", Swarm);
}