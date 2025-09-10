package hrt.prefab.fx.gpuemitter;

class RandomColorSpawnShader extends ComputeUtils {
	static var SRC = {

		@param var color1 : Int;
		@param var color2 : Int;

		@:import h3d.shader.ColorSpaces;

		var particleRandom : Float;
		var particleColor : Vec4;
		function main() {
			var idx = computeVar.globalInvocation.x;
			var fromColor = unpackIntColor(color1);
			var toColor = unpackIntColor(color2);
			particleColor = mix(fromColor, toColor, particleRandom);
		}
	}
}

class RandomColorSpawn extends SpawnShader {

	@:s var color1 : Int = 0xFFFFFFFF;
	@:s var color2 : Int = 0xFFFFFFFF;

	override function makeShader() {
		return new RandomColorSpawnShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		var sh = cast(shader, RandomColorSpawnShader);
		sh.color1 = color1;
		sh.color2 = color2;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Spawn">
				<dl>
					<dt>Color1</dt><dd><input type="color" alpha=true field="color1"/></dd>
					<dt>Color2</dt><dd><input type="color" alpha=true field="color2"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("randomColorSpawn", RandomColorSpawn);
}