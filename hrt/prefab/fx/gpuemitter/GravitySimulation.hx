package hrt.prefab.fx.gpuemitter;

class GravitySimulationShader extends ComputeUtils {
	static var SRC = {
		@param var gravity : Vec3;

		var speed : Vec3;
		var dt : Float;
		function main() {
			speed += dt * gravity * 9.81;
		}
	}
}

class GravitySimulation extends SimulationShader {
	@:s var gravityX : Float = 0.0;
	@:s var gravityY : Float = 0.0;
	@:s var gravityZ : Float = -1.0;

	override function makeShader() {
		return new GravitySimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, GravitySimulationShader);
		sh.gravity.set(gravityX, gravityY, gravityZ);
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<category("Simulation")>
				<line label="Gravity">
					<range(-1, 1) label="X" field={gravityX}/>
					<range(-1, 1) label="Y" field={gravityY}/>
					<range(-1, 1) label="Z" field={gravityZ}/>
				</line>
			</category>
		);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>Gravity X</dt><dd><input type="range" min="-1" max="1" field="gravityX"/></dd>
					<dt>Gravity Y</dt><dd><input type="range" min="-1" max="1" field="gravityY"/></dd>
					<dt>Gravity Z</dt><dd><input type="range" min="-1" max="1" field="gravityZ"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("gravitySimulation", GravitySimulation);
}