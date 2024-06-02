package hrt.prefab.fx.gpuemitter;

class OrbitSpeedSimulationShader extends ComputeUtils {
	override function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {
		super.onUpdate(emitter, buffer, index);
	}

	static var SRC = {
		@param var axis : Vec3;

		var speed : Vec3;
		var lifeTime : Float;
		var prevModelView : Mat4;
		var modelView : Mat4;
		var dt : Float;

		function main() {
			var idx = computeVar.globalInvocation.x;
			var prevPos = vec3(0.0) * prevModelView.mat3x4();
			var radialDir = prevPos;
			var radius = length(radialDir);
			radialDir = radialDir - radialDir.dot(axis) * axis;
			radialDir = normalize(radialDir);
			var spherical = cartesianToSpherical(radialDir);
			var theta = spherical.y;
			var phi = spherical.z + PI * 0.5;
			speed = vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

			var dir = normalize(speed);

			var newPos = normalize(prevPos + dt * speed) * radius;
			speed = (newPos - prevPos) / dt;
		}
	}
}

class OrbitSpeedSimulation extends SimulationShader {
	@:s var axisX : Float = 0.0;
	@:s var axisY : Float = 0.0;
	@:s var axisZ : Float = 1.0;

	override function makeShader() {
		return new OrbitSpeedSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, OrbitSpeedSimulationShader);
		sh.axis.set(axisX, axisY, axisZ);
		sh.axis.normalize();
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>X</dt><dd><input type="range" min="-1" max="1" value="0" field="axisX"/></dd>
					<dt>Y</dt><dd><input type="range" min="-1" max="1" value="0" field="axisY"/></dd>
					<dt>Z</dt><dd><input type="range" min="-1" max="1" value="0" field="axisZ"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("orbitSpeedSimulation", OrbitSpeedSimulation);
}