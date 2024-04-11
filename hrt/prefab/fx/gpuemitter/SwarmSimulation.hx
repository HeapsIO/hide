package hrt.prefab.fx.gpuemitter;

class SwarmSimulationShader extends ComputeUtils {
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
		primitiveTransform.load(@:privateAccess emitter.data.trs);
		emitterCenter.load(emitter.getAbsPos().getPosition());
	}

	static var SRC = {
		@param var primitiveTransform : Mat4;
		@param var emitterCenter : Vec3;

		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		var dt : Float;
		function main() {
			var idx = computeVar.globalInvocation.x;
			var radialDir = vec3(0.0) * modelView.mat3x4();
			var radius = length(radialDir);
			radialDir.z = 0.0;
			radialDir = normalize(radialDir);
			var spherical = cartesianToSpherical(radialDir);
			var theta = spherical.y;
			var phi = spherical.z + PI * 0.5;
			speed = vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

			var dir = normalize(speed);

			var pos = vec3(0.0) * modelView.mat3x4();
			pos += dt * speed;
			pos = normalize(pos) * radius;
			modelView = primitiveTransform * alignMatrix(vec3(0.0, 0.0, 1.0), dir) * translationMatrix(pos);
		}
	}
}

class SwarmSimulation extends SimulationShader {
	@:s var radius : Float = 1.0;
	@:s var startSpeed : Float = 1.0;

	override function makeShader() {
		return new SwarmSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, SwarmSimulationShader);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("swarmSimulation", SwarmSimulation);
}