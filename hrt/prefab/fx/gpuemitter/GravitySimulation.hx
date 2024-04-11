package hrt.prefab.fx.gpuemitter;

class GravitySimulationShader extends ComputeUtils {
	static var SRC = {
		@param var gravity : Float;

		var speed : Vec3;
		var lifeTime : Float;
		var modelView : Mat4;
		var dt : Float;
		function main() {
			speed.z -= dt * gravity; 
		}
	}
}

class GravitySimulation extends SimulationShader {
	@:s var gravity : Float = 1.0;

	override function makeShader() {
		return new GravitySimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, GravitySimulationShader);
		sh.gravity = gravity;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>Gravity</dt><dd><input type="range" min="0.0" max="10" field="gravity"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("gravitySimulation", GravitySimulation);
}