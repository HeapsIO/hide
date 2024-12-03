package hrt.prefab.fx.gpuemitter;

class SphereSpawnShader extends ComputeUtils {
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		randOffset = index;
	}

	static var SRC = {
		@param var minRadius : Float;
		@param var maxRadius : Float;
		@param var randOffset : Int;

		var emitNormal : Vec3;
		var relativeTransform : Mat4;
		function main() {
			var rnd = random3d(vec2(global.time, computeVar.globalInvocation.x + randOffset));
			var theta = rnd.y * PI;
			var phi = rnd.z * 2.0 * PI;
			var dir = sphericalToCartesian(1.0, theta, phi);
			emitNormal = dir;
			relativeTransform = translationMatrix(dir * mix(minRadius, maxRadius, rnd.x));
		}
	}
}

class SphereSpawn extends SpawnShader {
	@:s var minRadius : Float = 0.2;
	@:s var maxRadius : Float = 1.0;

	override function makeShader() {
		return new SphereSpawnShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, SphereSpawnShader);
		sh.minRadius = minRadius;
		sh.maxRadius = maxRadius;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Spawn">
				<dl>
					<dt>Min radius</dt><dd><input type="range" min="0.1" max="10" field="minRadius"/></dd>
					<dt>Max radius</dt><dd><input type="range" min="0.1" max="10" field="maxRadius"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("sphereSpawn", SphereSpawn);
}