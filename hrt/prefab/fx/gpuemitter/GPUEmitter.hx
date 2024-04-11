package hrt.prefab.fx.gpuemitter;

class PropsShader extends hxsl.Shader {
	static var SRC = {
		@perInstance @param var speed : Vec3;
		@perInstance @param var lifeTime : Float;

		var pixelColor : Vec4;
		function fragment() {
			// TODO build buffer with struct so DCE can't change buffer format.
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
}

@:allow(hrt.prefab.fx.GPUEmitter)
class GPUEmitterObject extends h3d.scene.MeshBatch {
	public var simulationPass : h3d.mat.Pass;
	public var spawnPass : h3d.mat.Pass;

	var data : Data;
	var propsShader : PropsShader;

	public function new(data, primitive, materials, ?parent) {
		super(primitive, null, parent);
		allowGpuUpdate = true;
		if ( materials != null )
			this.materials = materials;
		propsShader = new PropsShader();
		for ( m in this.materials ) {
			m.mainPass.addShader(propsShader);
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
		var p = dataPasses;
		trace("Max count is ", data.maxCount);
		while ( p != null ) {
			trace("Max instance is ", p.maxInstance);
			trace(p.pass.name + " pass has estimated " + Math.ceil(data.maxCount / p.maxInstance) + " buffers");
			p = p.next;
		}
	}

	function dispatch(ctx : h3d.scene.RenderContext) {
		#if editor
		return;
		#end
		var p = dataPasses;
		while ( p != null ) {
			var baseSpawn = spawnPass.getShader(BaseSpawn);
			baseSpawn.MAX_INSTANCE_COUNT = p.maxInstance;
			baseSpawn.maxLifeTime = data.maxLifeTime;
			baseSpawn.minLifeTime = data.minLifeTime;

			var baseSimulation = simulationPass.getShader(BaseSimulation);
			baseSimulation.INFINITE = data.infinite;
			baseSimulation.dtParam = ctx.elapsedTime;
			baseSimulation.MAX_INSTANCE_COUNT = p.maxInstance;

			for ( i => b in p.buffers ) {
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
			}
			p = p.next;
		}
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		super.sync(ctx);
	}

	override function emit(ctx : h3d.scene.RenderContext) {
		dispatch(ctx);
		super.emit(ctx);
	}
}

class GPUEmitter extends Object3D {
	static function getDefaultPrimitive() {
		return h3d.prim.Cube.defaultUnitCube();
	}

	@:s var maxCount : Int = 512; 
	@:s var minLifeTime : Float = 0.5; 
	@:s var maxLifeTime : Float = 5.0;
	@:s var gravity : Float = 1.0; 
	@:s var radius : Float = 1.0; 
	@:s var startSpeed : Float = 1.0; 
	@:s var infinite : Bool = false; 

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

	override function makeChild(c : hrt.prefab.Prefab) {
		#if !editor
		if ( Std.isOfType(c, hrt.prefab.Object3D) )
			return;
		#end
		super.makeChild(c);
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
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("gpuemitter", GPUEmitter);
}