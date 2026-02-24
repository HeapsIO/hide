package hrt.prefab.rfx;
@:access(h3d.scene.Renderer)

class Outline extends RendererFX {
	public var outlineColor : Int = 0xFFFFFF;

	var outlineShader = new h3d.pass.ScreenFx(new hide.Renderer.ScreenOutline());
	var outlineBlur = new h3d.pass.Blur(4);

	function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	function getInput(r : h3d.scene.Renderer) {
		var ldrCopy = r.allocTarget("ldrCopy", true, 1.0);
		h3d.pass.Copy.run(r.ctx.engine.getCurrentTarget(), ldrCopy);
		return ldrCopy;
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if (step != BeforeTonemapping)
			return;

		r.mark("Outline");

		var outlineTex = r.allocTarget("outline", true);
		r.ctx.engine.pushTarget(outlineTex);
		r.clear(0);
		r.draw("highlightBack");
		r.draw("highlight");
		r.ctx.engine.popTarget();
		var outlineBlurTex = r.allocTarget("outlineBlur", false);
		outlineShader.pass.setBlendMode(Alpha);
		outlineShader.shader.outlineColor = h3d.Vector.fromColor(outlineColor);
		outlineBlur.apply(r.ctx, outlineTex, outlineBlurTex);
		outlineShader.shader.texture = outlineBlurTex;
		outlineShader.render();
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<root>
				<category("Outline")>
				</category>
			</root>
		);
	}

	static var _ = Prefab.register("rfx.outline", Outline);

}
