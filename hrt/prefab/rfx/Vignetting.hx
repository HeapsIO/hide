package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
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

@:access(h3d.scene.Renderer)
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

	override function modulate(t : Float) {
		var v : Vignetting = cast super.modulate(t);
		v.alpha = this.alpha * t;
		return v;
	}

	// override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
	// 	var c1 : Vignetting = cast r1;
	// 	var c2 : Vignetting = cast r2;
	// 	var c = new ColorGrading(null, null);
	// 	c.customLutsBlend = { from : @:privateAccess c1.customLut == null ? c1.getLutTexture() : c1.customLut, to: @:privateAccess c2.customLut == null ? c2.getLutTexture() : c2.customLut };
	// 	var blendTonemap = new ColorGradingTonemapBlend();
	// 	blendTonemap.blendFactor = 0.;
	// 	c.tonemap = blendTonemap;
	// 	c.size = c1.size;
	// 	c.texturePath = c2.texturePath;
	// 	c.intensity = c1.intensity;
	// 	return { effect : cast c, setFactor : (f : Float) -> {
	// 		blendTonemap.blendFactor = f;
	// 		c.size = hxd.Math.round(hxd.Math.lerp(c1.size, c2.size, f));
	// 		c.intensity = hxd.Math.lerp(c1.intensity, c2.intensity, f);
	// 	} };
	// }

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<dt>Color</dt><dd><input type="color" field="color"/></dd>
				<dt>Alpha</dt><dd><input type="range" min="0" max="1" field="alpha"/></dd>
				<dt>Radius</dt><dd><input type="range" min="0" max="1" field="radius"/></dd>
				<dt>Softness</dt><dd><input type="range" min="0" max="1" field="softness"/></dd>
			</dl>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
		super.edit(ctx);
	}
	#end

	static var _ = Prefab.register("rfx.Vignetting", Vignetting);

}