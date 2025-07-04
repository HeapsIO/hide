package hrt.prefab.fx.gpuemitter;

import hrt.prefab.fx.gpuemitter.GPUEmitter.Data;
import hrt.prefab.fx.gpuemitter.CubeSpawn.CubeSpawnShader;

class ParticleShader extends hxsl.Shader {
	static var SRC = {
		@param var localTransform : Mat4;
		@param var absPos : Mat4;

		@param var particleBuffer : RWPartialBuffer<{
			life : Float,
			lifeTime : Float,
			random : Float,
			color : Float,
		}>;

		@:import h3d.shader.ColorSpaces;

		@flat var particleLife : Float;
		@flat var particleLifeTime : Float;
		@flat var particleRandom : Float;
		@flat var particleColor : Vec4;

		var relativePosition : Vec3;
		var transformedPosition : Vec3;
		function __init__vertex() {
			{
				particleLife = particleBuffer[instanceID].life;
				particleLifeTime = particleBuffer[instanceID].lifeTime;
				particleRandom = particleBuffer[instanceID].random;
				particleColor = int2rgba(floatBitsToInt(particleBuffer[instanceID].color));
			}
			transformedPosition = transformedPosition * absPos.mat3x4();
		}

		function vertex() {
			relativePosition = relativePosition * localTransform.mat3x4();
		}

		var pixelColor : Vec4;
		function fragment() {
			pixelColor *= particleColor;
		}
	}
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

	var particleBuffer : h3d.Buffer;
	var particleShader : ParticleShader;
	var particleCounter : h3d.GPUCounter;

	var rateAccumulation : Float = 0.0;
	var firstDispatch : Bool = true;

	public var gameplayRate(default, set) : Float = 1.0;
	public function set_gameplayRate(v : Float) {
		return gameplayRate = hxd.Math.clamp(v);
	}

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

		enableGpuUpdate();
		enableStorageBuffer();
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

	function init() {
		var alloc = hxd.impl.Allocator.get();
		var particleBufferFormat = hxd.BufferFormat.make([
			{ name : "speed", type : DVec3 },
			{ name : "life", type : DFloat },
			{ name : "lifeTime", type : DFloat },
			{ name : "random", type : DFloat },
			{ name : "color", type : DFloat },
			{ name : "padding", type : DFloat },
		]);

		if ( particleBuffer == null ) {
			var stride = particleBufferFormat.stride;
			var floats = alloc.allocFloats(data.maxCount * stride);
			for ( i in 0...data.maxCount ) {
				// speed
				// floats[i * stride] = 0.0;
				// floats[i * stride + 1] = 0.0;
				// floats[i * stride + 2] = 0.0;
				var l = hxd.Math.random() * (data.maxLifeTime - data.minLifeTime) + data.minLifeTime;
				floats[i * stride + 3] = l; // life warmup
				floats[i * stride + 4] = l; // lifeTime
				floats[i * stride + 5] = hxd.Math.random(); // random
				// color
				// floats[i * stride + 6] = 0.0;
				// padding
				// floats[i * stride + 7] = 0.0;
			}
			particleBuffer = alloc.ofFloats(floats, particleBufferFormat, UniformReadWrite);
			particleCounter = new h3d.GPUCounter();
			particleShader.particleBuffer = particleBuffer;
		}

		begin();
		for ( _ in 0...data.maxCount )
			emitInstance();
	}

	function createUpdateParamShader() {
		return { shader : null, params : null, size : null };
	}

	function dispatch(ctx : h3d.scene.RenderContext) {
		#if editor
		return;
		#end

		var p = dataPasses;
		particleCounter.reset();

		while ( p != null ) {
			var baseSpawn = spawnPass.getShader(BaseSpawn);
			baseSpawn.maxLifeTime = data.maxLifeTime;
			baseSpawn.minLifeTime = data.minLifeTime;
			baseSpawn.maxStartSpeed = data.maxStartSpeed;
			baseSpawn.minStartSpeed = data.minStartSpeed;
			baseSpawn.FORCED = data.infinite && firstDispatch;
			baseSpawn.INFINITE = data.infinite;
			if ( data.rate > 0 ) {
				var r = data.rate * ctx.elapsedTime;
				baseSpawn.rate = Math.floor(r);
				if ( baseSpawn.rate == 0 ) {
					baseSpawn.rate = Math.floor(rateAccumulation);
					if ( baseSpawn.rate == 0 )
						rateAccumulation += r;
					else
						rateAccumulation = 0.0;
				} else
					rateAccumulation = 0.0;
			} else
				baseSpawn.rate = instanceCount;
			switch ( data.speedMode ) {
			case Normal:
				baseSpawn.SPEED_NORMAL = true;
			case None:
				baseSpawn.SPEED_NORMAL = false;
			}

			var baseSimulation = simulationPass.getShader(BaseSimulation);
			baseSimulation.dtParam = ctx.elapsedTime;
			baseSimulation.maxSize = data.maxSize;
			baseSimulation.minSize = data.minSize;
			switch ( data.align ) {
			case FaceCam:
				baseSimulation.FACE_CAM = true;
			case Speed:
				baseSimulation.FACE_CAM = false;
			}
			baseSimulation.cameraUp.load(ctx.camera.getUp());
			baseSimulation.curCount = Math.floor(instanceCount * gameplayRate);

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
				var d = data.cameraModeDistance;
				var bounds = h3d.col.Bounds.fromValues(camPos.x - d * 0.5,
					camPos.y - d * 0.5,
					camPos.z - d * 0.5,
					d,
					d,
					d);
				baseSimulation.boundsPos.set(bounds.xMin, bounds.yMin, bounds.zMin);
				baseSimulation.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);

				var cubeSpawn = spawnPass.getShader(CubeSpawnShader);
				if ( cubeSpawn == null ) {
					cubeSpawn = new CubeSpawnShader();
					spawnPass.addShader(cubeSpawn);
				}
				cubeSpawn.boundsMin.set(bounds.xMin, bounds.yMin, bounds.zMin);
				cubeSpawn.boundsSize.set(bounds.xSize, bounds.ySize, bounds.zSize);
			}
			baseSimulation.CAMERA_BOUNDS = data.mode == Camera;

			var i = 0;
			for ( b in p.buffers ) {
				if ( b.isDisposed() )
					continue;

				for ( s in spawnPass.getShaders() ) {
					var computeUtils = Std.downcast(s, ComputeUtils);
					if ( computeUtils != null )
						computeUtils.onDispatch(this);
				}

				for ( s in simulationPass.getShaders() ) {
					var computeUtils = Std.downcast(s, ComputeUtils);
					if ( computeUtils != null )
						computeUtils.onDispatch(this);
				}

				baseSpawn.batchBuffer = b;
				baseSpawn.particleBuffer = particleBuffer;
				baseSpawn.atomic = particleCounter.buffer;

				baseSimulation.batchBuffer = b;
				baseSimulation.particleBuffer = particleBuffer;

				ctx.computeList(@:privateAccess spawnPass.shaders);
				ctx.computeDispatch(instanceCount);

				ctx.computeList(@:privateAccess simulationPass.shaders);
				ctx.computeDispatch(instanceCount);

				for ( row => p in shaderParams ) {
					p.shader.paramTexture = paramTexture;
					p.shader.batchBuffer = b;
					p.shader.particleBuffer = particleBuffer;
					p.shader.stride = b.format.stride;
					p.shader.row = (row + 0.5) / shaderParams.length;
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
		}
		firstDispatch = false;
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		switch (data.mode) {
		case Camera:
			fxAnim.autoCull = false;
			ignoreParentTransform = true;
			setPosition(ctx.camera.pos.x, ctx.camera.pos.y, ctx.camera.pos.z);
		default:
			ignoreParentTransform = false;
		}
		super.sync(ctx);
	}

	override function emit(ctx : h3d.scene.RenderContext) {
		dispatch(ctx);
		particleShader.localTransform.load(data.trs);
		super.emit(ctx);
	}

	override function onRemove() {
		super.onRemove();

		if ( particleBuffer != null ) {
			particleBuffer.dispose();
			particleBuffer = null;
		}

		if(particleCounter != null) {
			particleCounter.dispose();
			particleCounter = null;
		}

		if ( paramTexture != null )
			paramTexture.dispose();

		for ( s in spawnPass.getShaders() ) {
			var computeUtils = Std.downcast(s, ComputeUtils);
			if ( computeUtils != null )
				computeUtils.onRemove(this);
		}

		for ( s in simulationPass.getShaders() ) {
			var computeUtils = Std.downcast(s, ComputeUtils);
			if ( computeUtils != null )
				computeUtils.onRemove(this);
		}
	}
}