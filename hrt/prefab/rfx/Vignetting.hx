package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
import hrt.prefab.Library;
import hxd.Math;

class VignettingShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@param var color : Vec4;
		@param var radius : Float;
		@param var softness : Float;

		function fragment() {
			var pos = uvToScreen(calculatedUV);
			var dist = length(pos);
			var intensity = 1 - smoothstep(radius, radius-softness, dist);
			var alpha = color.a * intensity;
			pixelColor = vec4(color.rgb, alpha);
		}
	}
}

class Vignetting extends RendererFX {

	var vignettingPass = new h3d.pass.ScreenFx(new VignettingShader());

	@:s public var color : Int = 0xFFFFFF;
	@:s public var alpha : Float = 1;
	@:s public var radius : Float = 1;
	@:s public var softness : Float;

	function sync( r : h3d.scene.Renderer ) {
		var ctx = r.ctx;
		vignettingPass.shader.color.setColor(color);
		vignettingPass.shader.color.a = alpha;
		vignettingPass.shader.radius = radius;
		vignettingPass.shader.softness = softness;
		vignettingPass.pass.setBlendMode(Alpha);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( step == AfterTonemapping ) {
			r.mark("Vignetting");
			sync(r);
			vignettingPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<dt>Color</dt><dd><input type="color" field="color"/></dd>
				<dt>Alpha</dt><dd><input type="range" min="0" max="1" field="alpha"/></dd>
				<dt>Radius</dt><dd><input type="range" min="0" max="1" field="radius"/></dd>
				<dt>Softness</dt><dd><input type="range" min="0" max="1" field="softness"/></dd>
			</dl>
		'),this);
		super.edit(ctx);
	}
	#end

	static var _ = Library.register("rfx.Vignetting", Vignetting);

}