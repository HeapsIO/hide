package hrt.prefab.rfx;

class ChromaticAberrationShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@const var DEBUG : Bool;

		@param var opacity : Float;
		@param var radius : Float;
		@param var softness : Float;
		@param var intensity : Float;

		@param var ldrCopy : Sampler2D;

		function fragment() {
			var pos = uvToScreen(calculatedUV);
			var dist = length(pos);
			var dir = normalize(pos);
			var vignettingOpacity = 1 - smoothstep(radius, radius-softness, dist);

			var red = ldrCopy.get(calculatedUV + dir * vignettingOpacity * intensity).r;
			var green = ldrCopy.get(calculatedUV).g;
			var blue = ldrCopy.get(calculatedUV - dir * vignettingOpacity * intensity).b;
			pixelColor.rgb = vec3(red, green, blue);
			pixelColor.a = opacity;

			if ( DEBUG ) {
				pixelColor.rgb = vec3(pixelColor.a * vignettingOpacity);
				pixelColor.a = 1.0;
			}
		}
	}
}

@:access(h3d.scene.Renderer)
class ChromaticAberration extends RendererFX {

	@:s var DEBUG : Bool = false;
	@:s var opacity : Float = 1.0;
	@:s var intensity : Float = 1.0;
	@:s var radius : Float = 1.0;
	@:s var softness : Float = 0.2;

	var pass = new h3d.pass.ScreenFx(new ChromaticAberrationShader());

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if ( step == AfterTonemapping ) {
			r.mark("ChromaticAberration");

			var ldrCopy = r.allocTarget("ldrCopy", true, 1.0);
			h3d.pass.Copy.run(r.ctx.engine.getCurrentTarget(), ldrCopy);
			pass.shader.ldrCopy = ldrCopy;

			pass.shader.DEBUG = DEBUG;
			pass.shader.opacity = opacity;
			pass.shader.radius = radius;
			pass.shader.softness = softness;
			pass.shader.intensity = intensity * 0.01;

			pass.pass.setBlendMode(Alpha);
			pass.render();
		}
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Aberration">
				<dl>
					<dt>Intensity [%]</dt><dd><input type="range" min="0" max="3" field="intensity"/></dd>
				</dl>
			</div>
			<div class="group" name="Vignetting">
				<dl>
					<dt>DEBUG</dt><dd><input type="checkbox" field="DEBUG"/></dd>
					<dt>Opacity</dt><dd><input type="range" min="0" max="1" field="opacity"/></dd>
					<dt>Radius</dt><dd><input type="range" min="0" max="1" field="radius"/></dd>
					<dt>Softness</dt><dd><input type="range" min="0" max="1" field="softness"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Aberration")>
					<range(0, 3) label="Intensity [%]" field={intensity}/>
				</category>
				<category("Vignetting")>
					<checkbox field={DEBUG}/>
					<range(0, 1) field={opacity}/>
					<range(0, 1) field={radius}/>
					<range(0, 1) field={softness}/>
				</category>
			</root>
		);
	}

	static var _ = Prefab.register("rfx.chromaticAberration", ChromaticAberration);

}