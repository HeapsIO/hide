package hrt.prefab.fx.gpuemitter;

class MeshSpawnShader extends ComputeUtils {

	public var mesh(default, null) : h3d.scene.Mesh;
	
	public function attachTo(m : h3d.scene.Mesh) {
		if ( vbuf != null )
			vbuf.dispose();
		mesh = m;
		
		var originalBuffer = mesh.primitive.buffer;
		
		vertexCount = hxd.Math.imin(128, originalBuffer.vertices);
		vertexCount = originalBuffer.vertices;
		var skip = Math.floor(originalBuffer.vertices / vertexCount);

		var alloc = hxd.impl.Allocator.get();
		vbuf = alloc.allocBuffer(vertexCount, hxd.BufferFormat.make([
			{ name : "position", type : DVec3 },
			{ name : "normal", type : DVec3 },
		]), UniformReadWrite);

		var floatBuffer = alloc.allocFloats(vertexCount * vbuf.format.stride);
		var buffers = cast(mesh.primitive, h3d.prim.HMDModel).getDataBuffers(vbuf.format);
		for ( i in 0...vertexCount ) {
			for ( j in 0...vbuf.format.stride ) {
				floatBuffer[i * vbuf.format.stride + j] = buffers.vertexes.get(i * skip * vbuf.format.stride + j);
			}
		}
		vbuf.uploadFloats(floatBuffer, 0, vertexCount);
	}

	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		var parentInvert = new h3d.Matrix();
		parentInvert.load(emitter.parent.getAbsPos());
		parentInvert.invert();
		parentInvert.multiply3x4inline(mesh.getAbsPos(), parentInvert);
		emitter.setTransform(parentInvert);
	}

	static var SRC = {
		@param var vertexCount : Int;
		@param var vbuf : RWPartialBuffer<{ position : Vec3,
			normal : Vec3,
			// weights : Vec3,
			// indexes : Bytes4
		}>;
		// @param var bonesMatrixes : Array<Mat3x4,MaxBones>;
		@param var modelTransform : Mat4;

		var emitNormal : Vec3;
		var lifeTime : Float;
		var relativeTransform : Mat4;
		var relativePosition : Vec3;
		function main() {
			var idx = computeVar.globalInvocation.x;
			var vertexId = idx % vertexCount;
			emitNormal = vbuf[vertexId].normal;
			relativePosition = vbuf[vertexId].position;
			relativeTransform = translationMatrix(relativePosition);
		}
	}
}

class MeshSpawn extends SpawnShader {
	
	override function makeShader() {
		return new MeshSpawnShader();
	}

	override function postMakeInstance() {
		var sh = cast(shader, MeshSpawnShader);
		var mesh : h3d.scene.Mesh = null;
		for ( c in children ) {
			var obj3d = Std.downcast(c, Object3D);
			if ( obj3d == null )
				continue;
			mesh = obj3d.local3d.find(o -> Std.downcast(o, h3d.scene.Skin));
			if ( mesh != null )
				break;
		}
		if ( mesh == null ) {
			var defaultPrim = new h3d.prim.Sphere();
			defaultPrim.addUVs();
			defaultPrim.addNormals();
			mesh = new h3d.scene.Mesh(defaultPrim);
		}
		// Force primitive alloc
		if ( mesh.primitive.buffer == null )
			mesh.primitive.alloc(h3d.Engine.getCurrent());
		sh.attachTo(mesh);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Spawn">
				<dl>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("meshSpawn", MeshSpawn);
}