package hrt.prefab.fx.gpuemitter;

class LocalRotationShader extends ComputeUtils {

	static var SRC = {
		@param var speedRotation : Float;

		var relativeTransform : Mat4;
		var dt : Float;
		var life : Float;
		var particleRandom : Float;
		function main() {
			var r = 2.0 * random3d(vec2(particleRandom)) - 1.0;
			relativeTransform = rotateMatrixX(speedRotation * life * r.x) *
				rotateMatrixY(speedRotation * life * r.y) *
				rotateMatrixZ(speedRotation * life * r.z) *
				relativeTransform;
		}
	}
}

class LocalRotation extends SimulationShader {

	@:s var speedRotation : Float = 1.0;

	override function makeShader() {
		return new LocalRotationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, LocalRotationShader);
		sh.speedRotation = speedRotation * 2.0 * Math.PI;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>Rotation speed</dt><dd><input type="range" min="0" max="1" field="speedRotation"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("localRotation", LocalRotation);
}