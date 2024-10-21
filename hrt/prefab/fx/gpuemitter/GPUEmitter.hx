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

typedef ParticleBuffer = {
	var buffer : h3d.Buffer;
	var next : ParticleBuffer;
}

@:allow(hrt.prefab.fx.GPUEmitter)
class GPUEmitterObject extends h3d.scene.MeshBatch {
	public var simulationPass : h3d.mat.Pass;
	public var spawnPass : h3d.mat.Pass;
	public var updateParamPass : h3d.mat.Pass;
	public var data : Data;
	public var fxAnim : hrt.prefab.fx.FX.FXAnimation;

	var customAnimations : Array<hrt.prefab.fx.BaseFX.CustomAnimation> = [];
	var shaderParams : Array<{ param : hrt.prefab.fx.BaseFX.ShaderParam, shader : UpdateParamShader }> = [];
	var paramTexture : h3d.mat.Texture;

	var particleBuffers : ParticleBuffer; 

	var particleShader : ParticleShader;

	public function new(data, primitive, materials, ?parent) {
		super(primitive, null, parent);
		fxAnim = null;
		var p = parent;
		while ( p != null ) {
			fxAnim = Std.downcast(p, hrt.prefab.fx.FX.FXAnimation);
			if ( fxAnim != null )
				break;
			p = p.parent;
		}
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
		for ( _ in 0...data.maxCount )
			emitInstance();
	}

	override function flush(ctx : h3d.scene.RenderContext) {
		super.flush(ctx);

		var alloc = hxd.impl.Allocator.get();
		if ( particleBuffers == null )
			particleBuffers = { buffer : null, next : null};
		var particleBuffer = particleBuffers;
		var p = dataPasses;
		var particleBufferFormat = hxd.BufferFormat.make([
			{ name : "speed", type : DVec3 },
			{ name : "lifeTime", type : DVec4 }]
		);
		while ( p != null ) {
			if ( particleBuffer.buffer == null )
				particleBuffer.buffer = alloc.allocBuffer(instanceCount, particleBufferFormat, UniformReadWrite);
			p = p.next;
			if ( p != null && particleBuffer.next == null ) {
				particleBuffer.next = { buffer : null, next : null};
			}

			particleBuffer = particleBuffer.next;
		}
	}

	public function bakeAnimations() {
		if ( paramTexture != null )
			paramTexture.dispose();

		var prec = 255;
		var data : Array<{param : hrt.prefab.fx.BaseFX.ShaderParam, values : Array<Dynamic>}> = [];
		for ( anim in customAnimations ) {
			var shaderAnimation = Std.downcast(anim, hrt.prefab.fx.BaseFX.ShaderAnimation);
			if ( shaderAnimation == null )
				continue;
			for ( p in shaderAnimation.params ) {
				var values = [];
				for ( i in 0...prec ) {
					shaderAnimation.setTime(i / prec);
					values.push(shaderAnimation.shader.getParamValue(p.idx));
				}
				data.push({param : p, values : values});
				if ( updateParamPass == null )
					updateParamPass = new h3d.mat.Pass("paramUpdate");
				var shader = new UpdateParamShader();
				updateParamPass.addShader(shader);
				shaderParams.push({ param : p, shader : shader });
			}
		}

		if ( data.length > 0 ) {
			paramTexture = new h3d.mat.Texture(prec, data.length, null, RGBA32F);
			var pxls = hxd.Pixels.alloc(prec, data.length, RGBA32F);
			for ( row => d in data ) {
				if ( Std.isOfType(d.values[0], h3d.Vector4.Vector4Impl) ) {
					for ( i in 0...prec )
						pxls.setPixelF(i, row, d.values[i]);
				} else if ( Std.isOfType(d.values[0], h3d.Vector.VectorImpl) ) {
					for ( i in 0...prec ) {
						pxls.setPixelF(i, row, cast(d.values[i], h3d.Vector.VectorImpl).toVector4());
					}
				} else {
					for ( i in 0...prec )
						pxls.setPixelF(i, row, new h3d.Vector4(d.values[i]));
				}
			}
			paramTexture.uploadPixels(pxls);
		}
	}

	function createUpdateParamShader() {
		return { shader : null, params : null, size : null };
	}

	function dispatch(ctx : h3d.scene.RenderContext) {
		#if editor
		return;
		#end

		var p = dataPasses;
		var particleBuffer = particleBuffers;
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
				
				var camPos = ctx.camera.pos;
				var d = data.cameraModeDistance * 0.5;
				var bounds = h3d.col.Bounds.fromValues(camPos.x - d,
					camPos.y - d,
					camPos.z - d,
					2.0 * d,
					2.0 * d,
					2.0 * d);
				baseSimulation.boundsPos.set(bounds.xMin, bounds.yMin, bounds.zMin);
				baseSimulation.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);
				particleShader.absPos.load(getAbsPos());

				var cubeSpawn = spawnPass.getShader(CubeSpawnShader);
				if ( cubeSpawn == null ) {
					cubeSpawn = new CubeSpawnShader();
					spawnPass.addShader(cubeSpawn);
				}
				cubeSpawn.boundsMin.set(bounds.xMin, bounds.yMin, bounds.zMin);
				cubeSpawn.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);
			}
			switch (data.mode) {
			case Camera:
				fxAnim.autoCull = false;
			default:
				fxAnim.autoCull = true;
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
				baseSpawn.particleBuffer = particleBuffer.buffer;

				baseSimulation.batchBuffer = b;
				baseSimulation.particleBuffer = particleBuffer.buffer;

				ctx.computeList(@:privateAccess spawnPass.shaders);
				ctx.computeDispatch(instanceCount);

				ctx.computeList(@:privateAccess simulationPass.shaders);
				ctx.computeDispatch(instanceCount);

				for ( row => p in shaderParams ) {
					p.shader.paramTexture = paramTexture;
					p.shader.batchBuffer = b;
					p.shader.particleBuffer = particleBuffer.buffer;
					p.shader.stride = b.format.stride;
					p.shader.row = row;
					var pos = 0;
					for ( i in b.format.getInputs() ) {
						if ( i.name == p.param.def.name )
							break;
						pos += i.type.getSize();
					}
					p.shader.pos = pos;
				}
				if ( updateParamPass != null ) {
					ctx.computeList(@:privateAccess updateParamPass.shaders);
					ctx.computeDispatch(instanceCount);
				}

				i += p.maxInstance;
			}
			p = p.next;
			particleBuffer = particleBuffer.next;
		}
	}

	override function emit(ctx : h3d.scene.RenderContext) {
		dispatch(ctx);
		particleShader.localTransform.load(data.trs);
		super.emit(ctx);
	}

	override function cleanPasses() {
		super.cleanPasses();
		var b = particleBuffers;
		while ( b != null ) {
			b.buffer.dispose();
			b = b.next;
		}
		particleBuffers = null;
	}

	override function onRemove() {
		super.onRemove();

		if ( paramTexture != null )
			paramTexture.dispose();
	}
}

@:access(hrt.prefab.fx.gpuemitter.GPUEmitterObject)
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

	override function postMakeInstance() {
		super.postMakeInstance();

		var obj = local3d.find(o -> Std.downcast(o, GPUEmitterObject));
		if ( obj != null ) {
			obj.customAnimations = [];
			var shaders = findAll(hrt.prefab.Shader);
			for ( shader in shaders ) {
				if( !shader.enabled ) continue;
				hrt.prefab.fx.BaseFX.BaseFXTools.getCustomAnimations(shader, obj.customAnimations, obj.find(o -> Std.downcast(o, h3d.scene.MeshBatch)));
			}
			obj.bakeAnimations();
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