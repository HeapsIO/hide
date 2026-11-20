package hrt.prefab.fx.gpuemitter;

class OrbitSpeedSimulationShader extends ComputeUtils {
	public var localAxis = new h3d.Vector(0, 0, 1);

	override function onDispatch(emitter : GPUEmitterObject) {
		super.onDispatch(emitter);

		switch ( emitter.data.mode ) {
			case Local:
				center.set(0, 0, 0);
				axis.load(localAxis);
			case World, Camera:
				var absPos = emitter.getAbsPos();
				center.load(absPos.getPosition());
				axis.load(localAxis);
				axis.transform3x3(absPos);
		}
		axis.normalize();
	}

	static var SRC = {
		@param var axis : Vec3;
		@param var center : Vec3;
		@param var angularSpeed : Float;

		var speed : Vec3;
		var prevPos : Vec3;
		var dt : Float;

		function rotateAroundAxis(v : Vec3, angle : Float) : Vec3 {
			var c = cos(angle);
			var s = sin(angle);
			return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
		}

		function main() {
			var angle = angularSpeed * dt;
			prevPos = center + rotateAroundAxis(prevPos - center, angle);
			speed = rotateAroundAxis(speed, angle);
		}
	}
}

class OrbitSpeedSimulation extends SimulationShader {
	@:s var axisX : Float = 0.0;
	@:s var axisY : Float = 0.0;
	@:s var axisZ : Float = 1.0;
	@:s var speed : Float = 1.0;

	override function makeShader() {
		return new OrbitSpeedSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, OrbitSpeedSimulationShader);
		sh.localAxis.set(axisX, axisY, axisZ);
		sh.angularSpeed = speed;
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<category("Simulation")>
				<line label="Axis">
					<range(-1, 1) label="X" field={axisX}/>
					<range(-1, 1) label="Y" field={axisY}/>
					<range(-1, 1) label="Z" field={axisZ}/>
				</line>
				<slider label="Speed" field={speed}/>
			</category>
		);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>Axis X</dt><dd><input type="range" min="-1" max="1" field="axisX"/></dd>
					<dt>Axis Y</dt><dd><input type="range" min="-1" max="1" field="axisY"/></dd>
					<dt>Axis Z</dt><dd><input type="range" min="-1" max="1" field="axisZ"/></dd>
					<dt>Speed</dt><dd><input type="range" min="-10" max="10" field="speed"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("orbitSpeedSimulation", OrbitSpeedSimulation);
}
