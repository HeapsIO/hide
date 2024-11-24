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
		var fmt = if ( Std.isOfType(m, h3d.scene.Skin) ) {
			hxd.BufferFormat.make([
				{ name : "position", type : DVec3 },
				{ name : "padding", type : DFloat },
				{ name : "normal", type : DVec3 },
				{ name : "padding2", type : DFloat },
				{ name : "weights", type : DVec3 },
				{ name : "indexes", type : DBytes4 },
			]);
		} else {
			hxd.BufferFormat.make([
				{ name : "position", type : DVec3 },
				{ name : "padding", type : DFloat },
				{ name : "normal", type : DVec3 },
				{ name : "padding2", type : DFloat },
			]);
		}
		vbuf = alloc.allocBuffer(vertexCount, fmt, UniformReadWrite);

		var floatBuffer = alloc.allocFloats(vertexCount * vbuf.format.stride);
		var buffers = cast(mesh.primitive, h3d.prim.HMDModel).getDataBuffers(vbuf.format, [for ( i in 0...5) new h3d.Vector4()]);
		for ( i in 0...vertexCount ) {
			for ( j in 0...vbuf.format.stride ) {
				floatBuffer[i * vbuf.format.stride + j] = buffers.vertexes.get(i * skip * vbuf.format.stride + j);
			}
		}
		vbuf.uploadFloats(floatBuffer, 0, vertexCount);
	}

	var tmpMat : h3d.Matrix = new h3d.Matrix();
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		var parentInvert = new h3d.Matrix();
		parentInvert.load(emitter.parent.getAbsPos());
		parentInvert.invert();
		tmpMat.load(mesh.getAbsPos());
		if ( mesh.defaultTransform != null )
			tmpMat.multiply3x4inline(mesh.getAbsPos(), mesh.defaultTransform.getInverse());
		parentInvert.multiply3x4inline(tmpMat, parentInvert);
		emitter.setTransform(parentInvert);

		var skinShader = mesh.material.mainPass.getShader(h3d.shader.SkinBase);
		bonesMatrixes = skinShader.bonesMatrixes;
		MaxBones = skinShader.MaxBones;
		defaultMatrix = mesh.getAbsPos();
	}

	static var SRC = {
		@const var MaxBones : Int;

		@param var vertexCount : Int;
		@param var vbuf : RWPartialBuffer<{
			position : Vec3,
			padding : Float,
			normal : Vec3,
			padding2 : Float,
			weights : Vec3,
			indexes : Bytes4
		}>;
		@param var bonesMatrixes : Array<Mat3x4,MaxBones>;
		@param var defaultMatrix : Mat4;

		var speed : Vec3;
		var emitNormal : Vec3;
		var relativeTransform : Mat4;
		function main() {
			var idx = computeVar.globalInvocation.x;
			var vertexId = idx % vertexCount;
			var vertexData = vbuf[vertexId];
			speed = vec3(1.0);
			var relativePosition = vertexData.position;
			var relativeNormal = vertexData.normal;
			
			var weights = vertexData.weights;
			weights = weights / (weights.x + weights.y + weights.z);
			var transformedPosition = (relativePosition * bonesMatrixes[int(vertexData.indexes.x * 127.0)]) * weights.x +
				(relativePosition * bonesMatrixes[int(vertexData.indexes.y * 127.0)]) * weights.y +
				(relativePosition * bonesMatrixes[int(vertexData.indexes.z * 127.0)]) * weights.z;

			var transformedNormal =
				(vertexData.normal * mat3(bonesMatrixes[int(vertexData.indexes.x * 127.0)])) * vertexData.weights.x +
				(vertexData.normal * mat3(bonesMatrixes[int(vertexData.indexes.y * 127.0)])) * vertexData.weights.y +
				(vertexData.normal * mat3(bonesMatrixes[int(vertexData.indexes.z * 127.0)])) * vertexData.weights.z;
			emitNormal = transformedNormal;
			
			relativeTransform = translationMatrix(transformedPosition);
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