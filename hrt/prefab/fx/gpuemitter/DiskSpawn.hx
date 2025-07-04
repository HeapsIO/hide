package hrt.prefab.fx.gpuemitter;

class DiskSpawnShader extends ComputeUtils {

	static var SRC = {
		@param var minRadius : Float;
		@param var maxRadius : Float;

		var emitNormal : Vec3;
		var relativeTransform : Mat4;
		function main() {
			var rnd = random2d(vec2(global.time, computeVar.globalInvocation.x));
			var theta = rnd.y * 2.0 * PI;
			var dir = vec3(cos(theta), sin(theta), 0.0);
			emitNormal = dir;
			relativeTransform = translationMatrix(dir * mix(minRadius, maxRadius, rnd.x));
		}
	}
}

class DiskSpawn extends SpawnShader {
	@:s var minRadius : Float = 0.2;
	@:s var maxRadius : Float = 1.0;

	override function makeShader() {
		return new DiskSpawnShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, DiskSpawnShader);
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

	static var _ = Prefab.register("DiskSpawn", DiskSpawn);
}