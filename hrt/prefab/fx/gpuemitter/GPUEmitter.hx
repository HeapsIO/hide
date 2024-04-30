package hrt.prefab.fx.gpuemitter;

import hrt.prefab.fx.gpuemitter.CubeSpawn.CubeSpawnShader;

enum Mode {
	World;
	Local;
	Camera;
}

enum Align {
	FaceCam;
	Speed;
}

enum SpeedMode {
	Normal;
	None;
}

class ParticleShader extends hxsl.Shader {
	static var SRC = {
		@perInstance @param var speed : Vec3;
		@perInstance @param var lifeTime : Float;

		@param var localTransform : Mat4;
		@param var absPos : Mat4;

		var relativePosition : Vec3;
		var transformedPosition : Vec3;
		function __init__vertex() {
			transformedPosition = transformedPosition * absPos.mat3x4();
		}

		function vertex() {
			relativePosition = relativePosition * localTransform.mat3x4();
		}

		var pixelColor : Vec4;
		function fragment() {
			pixelColor.rgb = packNormal(normalize(speed)).rgb * pixelColor.a * lifeTime;
		}
	}
}

typedef Data = {
	var maxCount : Int;
	var infinite : Bool;
	var maxLifeTime : Float;
	var minLifeTime : Float;
	var gravity : Float;
	var radius : Float;
	var startSpeed : Float;
	var trs : h3d.Matrix;
	var mode : Mode;
	var cameraModeDistance : Float;
	var align : Align;
	var speedMode : SpeedMode;
	var maxStartSpeed : Float;
	var minStartSpeed : Float;
}

@:allow(hrt.prefab.fx.GPUEmitter)
class GPUEmitterObject extends h3d.scene.MeshBatch {
	public var simulationPass : h3d.mat.Pass;
	public var spawnPass : h3d.mat.Pass;
	public var data : Data;
	
	var particleShader : ParticleShader;

	public function new(data, primitive, materials, ?parent) {
		super(primitive, null, parent);
		this.meshBatchFlags.set(EnableGpuUpdate);
		this.meshBatchFlags.set(EnableStorageBuffer);
		if ( materials != null )
			this.materials = materials;
		particleShader = new ParticleShader();
		for ( m in this.materials ) {
			m.mainPass.addShader(particleShader);
			m.shadows = false;
		}
		this.data = data;
		name = "gpuemitter";

		spawnPass = new h3d.mat.Pass("spawn");
		spawnPass.addShader(new BaseSpawn());

		simulationPass = new h3d.mat.Pass("simulation");
		simulationPass.addShader(new BaseSimulation());
		init();
	}

	public function init() {
		begin();
		for ( i in 0...data.maxCount )
			emitInstance();
	}

	function dispatch(ctx : h3d.scene.RenderContext) {
		#if editor
		return;
		#end
		var p = dataPasses;
		while ( p != null ) {
			var baseSpawn = spawnPass.getShader(BaseSpawn);
			baseSpawn.maxLifeTime = data.maxLifeTime;
			baseSpawn.minLifeTime = data.minLifeTime;
			baseSpawn.maxStartSpeed = data.maxStartSpeed;
			baseSpawn.minStartSpeed = data.minStartSpeed;
			switch ( data.speedMode ) {
			case Normal:
				baseSpawn.SPEED_NORMAL = true;
			case None:
				baseSpawn.SPEED_NORMAL = false;
			}

			var baseSimulation = simulationPass.getShader(BaseSimulation);
			baseSimulation.INFINITE = data.infinite;
			baseSimulation.dtParam = ctx.elapsedTime;
			switch ( data.align ) {
			case FaceCam:
				baseSimulation.FACE_CAM = true;
			case Speed:
				baseSimulation.FACE_CAM = false;
			}
			baseSimulation.cameraUp.load(ctx.camera.getUp());

			switch ( data.mode ) {
			case World:
				baseSpawn.absPos.load(getAbsPos());
				particleShader.absPos.identity();
			case Local:
				baseSpawn.absPos.identity();
				particleShader.absPos.load(getAbsPos());
			case Camera:
				baseSpawn.absPos.identity();
				particleShader.absPos.identity();
				
				var cam = ctx.camera.clone();
				cam.zFar = data.cameraModeDistance;
				cam.update();
				var bounds = new h3d.col.Bounds();
				bounds.addPoint(cam.unproject(-1, -1, 0.0).toPoint());
				bounds.addPoint(cam.unproject(1, 1, 0.0).toPoint());
				bounds.addPoint(cam.unproject(-1, -1, 1.0).toPoint());
				bounds.addPoint(cam.unproject(1, 1, 1.0).toPoint());
				baseSimulation.boundsPos.set(bounds.xMin, bounds.yMin, bounds.zMin);
				baseSimulation.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);
				particleShader.absPos.load(getAbsPos());

				var cubeSpawn = spawnPass.getShader(CubeSpawnShader);
				if ( cubeSpawn == null ) {
					cubeSpawn = new CubeSpawnShader();
					spawnPass.addShader(cubeSpawn);
				}
				cubeSpawn.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);
				cubeSpawn.boundsSize.set(bounds.getCenter().x, bounds.getCenter().y, bounds.getCenter().z);
			}
			baseSimulation.CAMERA_BOUNDS = data.mode == Camera;

			var i = 0;
			for ( b in p.buffers ) {
				if ( b.isDisposed() )
					continue;

				for ( s in spawnPass.getShaders() ) {
					var computeUtils = Std.downcast(s, ComputeUtils);
					if ( computeUtils != null )
						computeUtils.onUpdate(this, b, i);
				}

				for ( s in simulationPass.getShaders() ) {
					var computeUtils = Std.downcast(s, ComputeUtils);
					if ( computeUtils != null )
						computeUtils.onUpdate(this, b, i);
				}

				baseSpawn.batchBuffer = b;

				baseSimulation.batchBuffer = b;

				ctx.computeList(@:privateAccess spawnPass.shaders);
				ctx.computeDispatch(instanceCount);

				ctx.computeList(@:privateAccess simulationPass.shaders);
				ctx.computeDispatch(instanceCount);

				i += p.maxInstance;
			}
			p = p.next;
		}
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		super.sync(ctx);
	}

	override function emit(ctx : h3d.scene.RenderContext) {
		dispatch(ctx);
		particleShader.localTransform.load(data.trs);
		super.emit(ctx);
	}
}

class GPUEmitter extends Object3D {
	static function getDefaultPrimitive() {
		return h3d.prim.Cube.defaultUnitCube();
	}

	@:s var maxCount : Int = 512;
	@:s var minLifeTime : Float = 0.5;
	@:s var maxLifeTime : Float = 1.0;
	@:s var minStartSpeed : Float = 0.5;
	@:s var maxStartSpeed : Float = 1.0;
	@:s var gravity : Float = 1.0; 
	@:s var radius : Float = 1.0; 
	@:s var startSpeed : Float = 1.0; 
	@:s var infinite : Bool = false; 
	@:s var faceCam : Bool = false;
	@:s var mode : Mode = World;
	@:s var cameraModeDistance : Float = 50.0;
	@:s var align : Align = FaceCam;
	@:s var speedMode : SpeedMode = Normal;

	override function makeObject(parent3d : h3d.scene.Object) {
		return new h3d.scene.Object(parent3d);
	}

	function updateEmitters() {
		#if editor
		return;
		#end
		for ( emitter in local3d.findAll(o -> Std.downcast(o, GPUEmitterObject)) )
			emitter.remove();

		var meshes = [];
		for ( c in children ) {
			if ( !Std.isOfType(c, Object3D) )
				continue;
			var obj = new h3d.scene.Object();
			c.make(new ContextShared(obj));
			meshes = meshes.concat(obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh)));
		}
		inline function createEmitter(data, prim, materials) {
			new GPUEmitterObject(data, prim, materials, local3d);
		}
		inline function getData(trs : h3d.Matrix) {
			return {
				maxCount : maxCount,
				minLifeTime : minLifeTime,
				maxLifeTime : maxLifeTime,
				gravity : gravity,
				radius : radius,
				startSpeed : startSpeed,
				trs : trs,
				infinite : infinite,
				faceCam : faceCam,
				mode : mode,
				cameraModeDistance : cameraModeDistance,
				align : align,
				speedMode : speedMode,
				minStartSpeed : minStartSpeed,
				maxStartSpeed : maxStartSpeed,
			}
		}
		for ( mesh in meshes ) {
			var data = getData(mesh.getAbsPos().clone());
			var multimat = Std.downcast(mesh, h3d.scene.MultiMaterial);
			var materials : Array<h3d.mat.Material>;
			if ( multimat == null )
				materials = [mesh.material];
			else
				materials = multimat.materials;
			createEmitter(getData(mesh.getAbsPos().clone()), cast(mesh.primitive, h3d.prim.MeshPrimitive), materials);
			mesh.visible = false;
			mesh.ignoreCollide = true;
		}
		if ( meshes.length == 0 ) {
			var data = getData(h3d.Matrix.I());
			createEmitter(data, getDefaultPrimitive(), null);
		}
	}


	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		updateEmitters();
	}

	#if editor
	override function setSelected(b : Bool) {
		return false;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "asterisk",
		name : "GPUEmitter",
		allowParent : function(p) return p.to(FX) != null || p.findParent(FX) != null,
		onChildUpdate : function(p : hrt.prefab.Prefab) return updateEmitters(),
		};
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element('
			<div class="group" name="Emitter">
				<dl>
					<dt>Max count</dt><dd><input type="range" step="1" min="1" max="8192" field="maxCount"/></dd>
					<dt>Min life time</dt><dd><input type="range" min="0.1" max="10" field="minLifeTime"/></dd>
					<dt>Max life time</dt><dd><input type="range" min="0.1" max="10" field="maxLifeTime"/></dd>
					<dt>Infinite</dt><dd><input type="checkbox" field="infinite"/></dd>
					<dt>Face cam</dt><dd><input type="checkbox" field="faceCam"/></dd>
					<dt>Mode</dt>
					<dd>
						<select field="mode">
							<option value="World">World</option>
							<option value="Local">Local</option>
							<option value="Camera">Camera</option>
						</select>
					</dd>
					<dt>Camera distance</dt><dd><input type="range" min="0" field="cameraModeDistance"/></dd>
					<dt>Align</dt>
					<dd>
						<select field="align">
							<option value="FaceCam">Face cam</option>
							<option value="Speed">Speed</option>
						</select>
					</dd>
					<dt>Speed</dt>
					<dd>
						<select field="speedMode">
							<option value="Normal">Normal</option>
							<option value="None">None</option>
						</select>
					</dd>
					<dt>Min start speed</dt><dd><input type="range" min="0.1" max="10" field="minStartSpeed"/></dd>
					<dt>Max start speed</dt><dd><input type="range" min="0.1" max="10" field="maxStartSpeed"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("gpuemitter", GPUEmitter);
}