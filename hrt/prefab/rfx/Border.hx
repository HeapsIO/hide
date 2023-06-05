package hrt.prefab.rfx;

class BorderShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var size:Float;
		@param var color:Vec3;
		@param var alpha: Float;

		function fragment() {
			if ( calculatedUV.x > 1.0 - size || calculatedUV.x < size || calculatedUV.y > 1.0 - size || calculatedUV.y < size )
				pixelColor.rgba = vec4(color, alpha);
		}
	};
}

class Border extends RendererFX {
	public var pass : h3d.pass.ScreenFx<BorderShader>;

	public function new(parent: Prefab, shared: ContextShared, size = 0.1, color: Int = 0, alpha = 1.0) {
		super(parent, shared);
		var shader = new BorderShader();
		shader.size = size;
		shader.alpha = alpha;
		shader.color = h3d.Vector.fromColor(color);
		pass = new h3d.pass.ScreenFx(shader);
		pass.pass.setBlendMode(Alpha);
	}

	public override function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if ( step == AfterTonemapping )
			pass.render();
	}
}