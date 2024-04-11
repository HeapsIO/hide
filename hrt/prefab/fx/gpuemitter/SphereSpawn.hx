package hrt.prefab.fx.gpuemitter;

class SphereSpawnShader extends ComputeUtils {
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		absPos.multiply3x4inline(@:privateAccess emitter.data.trs, emitter.getAbsPos());
		randOffset = index;
	}

	static var SRC = {
		@param var absPos : Mat4;
		@param var radius : Float;
		@param var startSpeed : Float;
		@param var randOffset : Int;

		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		function main() {
			var rnd = random3d(vec2(global.time, computeVar.globalInvocation.x + randOffset));
			var r = rnd.x * radius;
			var theta = rnd.y * PI;
			var phi = rnd.z * 2.0 * PI;
			var dir = sphericalToCartesian(1.0, theta, phi);
			speed = dir * r / radius * startSpeed;
			var relPos = dir * r;
			modelView = absPos * translationMatrix(relPos);
		}
	}
}

class SphereSpawn extends SpawnShader {
	@:s var radius : Float = 1.0;
	@:s var startSpeed : Float = 1.0;

	override function makeShader() {
		return new SphereSpawnShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, SphereSpawnShader);
		sh.radius = radius;
		sh.startSpeed = startSpeed;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Spawn">
				<dl>
					<dt>Radius</dt><dd><input type="range" min="0.1" max="10" field="radius"/></dd>
					<dt>Start speed</dt><dd><input type="range" min="0.1" max="10" field="startSpeed"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("sphereSpawn", SphereSpawn);
}