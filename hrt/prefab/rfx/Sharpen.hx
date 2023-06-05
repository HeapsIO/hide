package hrt.prefab.rfx;

class SharpenShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@param var source : Sampler2D;
		@param var intensity : Float;
		@param var resolution : Vec2;

		function fragment() {

			var offset = 1.0 / resolution;
			var center = texture(source, calculatedUV);
			var sum = vec4(0);
			sum += texture(source, calculatedUV + vec2(0, offset.y));
			sum += texture(source, calculatedUV + vec2(-offset.x, 0));
			sum += texture(source, calculatedUV + vec2(offset.x, 0));
			sum += texture(source, calculatedUV + vec2(0, -offset.y) );

			// Return edge detection
			pixelColor = (1.0 + 4.0 * intensity) * center - intensity * sum;
		}
	}
}

@:access(h3d.scene.Renderer)
class Sharpen extends RendererFX {

	var sharpenPass = new h3d.pass.ScreenFx(new SharpenShader());
	@:s public var intensity : Float;

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == AfterTonemapping ) {
			r.mark("Sharpen");
			var sharpen = r.allocTarget("sharpen", true, 1.0, RGBA);
			var ctx = r.ctx;
			ctx.engine.pushTarget(sharpen);
			sharpenPass.shader.source = ctx.getGlobal("ldrMap");
			sharpenPass.shader.intensity = intensity;
			sharpenPass.shader.resolution.set(ctx.engine.width, ctx.engine.height);
			sharpenPass.render();
			ctx.engine.popTarget();
			ctx.setGlobal("ldrMap", sharpen);
			r.setTarget(sharpen);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Sharpen">
				<dl>
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				</dl>
			</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.sharpen", Sharpen);

}