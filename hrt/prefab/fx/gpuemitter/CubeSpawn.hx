package hrt.prefab.fx.gpuemitter;

class CubeSpawnShader extends ComputeUtils {
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		randOffset = index;
	}

	static var SRC = {
		@param var boundsMin : Vec3;
		@param var boundsSize : Vec3;
		@param var randOffset : Int;

		var emitNormal : Vec3;
		var lifeTime : Float;
		var relativeTransform : Mat4;
		function main() {
			var rnd = random3d(vec2(global.time, global.time * computeVar.globalInvocation.x + randOffset));
			relativeTransform = translationMatrix(rnd * boundsSize + boundsMin);
		}
	}
}

class CubeSpawn extends SpawnShader {
	@:s var cubeEdge : Float = 1.0;

	override function makeShader() {
		return new CubeSpawnShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, CubeSpawnShader);
		sh.boundsSize.set(cubeEdge, cubeEdge, cubeEdge);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Spawn">
				<dl>
					<dt>Cube edge</dt><dd><input type="range" min="0.1" max="10" field="cubeEdge"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("cubeSpawn", CubeSpawn);
}