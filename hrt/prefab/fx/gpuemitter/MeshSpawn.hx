package hrt.prefab.fx.gpuemitter;

class ComputeSkin extends hxsl.Shader {
	static var SRC = {
		@const(4095) var SIZE : Int;
		@param var vbuf : PartialBuffer<{ weights : Vec3, indexes : Bytes4 }, SIZE>;
		@param var bonesMatrixes : Array<Mat3, SIZE>;

		var relativePosition : Vec3;
		function main() {
			var v = vbuf[computeVar.globalInvocation.x];
			relativePosition = (relativePosition * bonesMatrixes[int(v.indexes.x)]) * v.weights.x +
			(relativePosition * bonesMatrixes[int(v.indexes.y)]) * v.weights.y +
			(relativePosition * bonesMatrixes[int(v.indexes.z)]) * v.weights.z;
		}
	}
}

class MeshSpawnShader extends ComputeUtils {
	public var mesh(default, null) : h3d.scene.Mesh;
	
	public function attachTo(m : h3d.scene.Mesh) {
		mesh = m;
		vbuf = mesh.primitive.buffer;
		SIZE = mesh.primitive.buffer.vertices;
	}

	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		offset = index;
		mult = Math.ceil(SIZE / emitter.data.maxCount);
		var parentInvert = new h3d.Matrix();
		parentInvert.load(emitter.parent.getAbsPos());
		parentInvert.invert();
		parentInvert.multiply3x4inline(mesh.getAbsPos(), parentInvert);
		emitter.setTransform(parentInvert);
	}

	static var SRC = {
		@const(4095) var SIZE : Int;
		@param var offset : Int;
		@param var mult : Int;
		@param var vbuf : PartialBuffer<{ position : Vec3, normal : Vec3 }, SIZE>;
		@param var modelTransform : Mat4;

		var emitNormal : Vec3;
		var lifeTime : Float;
		var relativeTransform : Mat4;
		var relativePosition : Vec3;
		function main() {
			var idx = computeVar.globalInvocation.x;
			var vertexId = ((idx + offset) * mult) % SIZE;
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

	// override function applyShader(obj : h3d.scene.Object, mat : h3d.mat.Material, sh : hxsl.Shader) {
	// 	super.applyShader(obj, mat, sh);
	// 	var gpuEmitter = Std.downcast(obj, GPUEmitter.GPUEmitterObject);
	// 	if ( gpuEmitter == null )
	// 		return;
	// 	var sh = cast(shader, MeshSpawnShader);
	// 	var prevSkin = gpuEmitter.spawnPass.getShader(h3d.shader.Skin);
	// 	if ( prevSkin != null )
	// 		gpuEmitter.spawnPass.removeShader(prevSkin);
	// 	if ( mesh != null ) {
	// 		var skinShader = mesh.material.mainPass.getShader(h3d.shader.Skin);
	// 		if ( skinShader != null ) {
	// 			var skinCompute = new ComputeSkin();
	// 			skinCompute.SIZE = sh.SIZE;
	// 			skinCompute.vbuf = sh.vbuf;
	// 			skinCompute.bonesMatrixes = skinShader.bonesMatrixes;
	// 			gpuEmitter.spawnPass.addShader(skinCompute);
	// 		}
	// 	}
	// }

	var mesh : h3d.scene.Mesh;
	override function makeChild(c) {
		if ( mesh != null )
			return;
		var object3D = Std.downcast(c, hrt.prefab.Object3D);
		if ( object3D == null )
			super.makeChild(c);
		else
			mesh = object3D.make().local3d.find(o -> Std.downcast(o, h3d.scene.Mesh));
	}

	override function postMakeInstance() {
		var sh = cast(shader, MeshSpawnShader);
		// var mesh = findFirstLocal3d().find(o -> Std.isOfType(o, GPUEmitter.GPUEmitterObject) ? null : Std.downcast(o, h3d.scene.Mesh));
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

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, MeshSpawnShader);
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