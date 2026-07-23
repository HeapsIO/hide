package hrt.prefab.rfx;
@:access(h3d.scene.Renderer)

class Outline extends RendererFX {
	public var color = 0xFF6600;

	var outlineShader = new h3d.pass.ScreenFx(new hide.Renderer.ScreenOutline());
	var outlineBlur = new h3d.pass.Blur(4);

	function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	public static function setHighlight(obj : h3d.scene.Object, visible : Bool = true) {
		var frontColor = new h3d.shader.FixedColor(0xFFFFFF, 1);
		var backColor = new h3d.shader.FixedColor(0xFF0000, 1);
		if (visible) {
			for (m in obj.getMaterials()) {
				var p = m.allocPass("highlight");
				p.culling = None;
				p.depthWrite = false;
				p.depthTest = LessEqual;
				p.addShader(frontColor);
				var p = m.allocPass("highlightBack");
				p.culling = None;
				p.depthWrite = false;
				p.depthTest = Always;
				p.addShader(backColor);
			}
		}
		else {
			for (m in obj.getMaterials()) {
				var p = m.getPass("highlight");
				if (p != null)
					m.removePass(p);
				p = m.getPass("highlightBack");
				if (p != null)
					m.removePass(p);
			}
		}
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
		outlineShader.shader.color = h3d.Vector.fromColor(color);
		outlineShader.pass.setBlendMode(Alpha);
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
