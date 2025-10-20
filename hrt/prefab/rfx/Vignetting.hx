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

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var v1 : Vignetting = cast r1;
		var v2 : Vignetting = cast r2;

		var v = new Vignetting(null, null);
		v.color = v1.color;
		v.alpha = v1.alpha;
		v.radius = v1.radius;
		v.softness = v1.softness;

		inline function lerpColor(c1 : Int, c2 : Int, f : Float) : Int {
			var a1 = (c1 >> 24) & 0xFF;
			var r1 = (c1 >> 16) & 0xFF;
			var g1 = (c1 >> 8) & 0xFF;
			var b1 = c1 & 0xFF;

			var a2 = (c2 >> 24) & 0xFF;
			var r2 = (c2 >> 16) & 0xFF;
			var g2 = (c2 >> 8) & 0xFF;
			var b2 = c2 & 0xFF;

    		inline function lerp(v1:Int, v2:Int, f:Float) : Int return Std.int(v1 * (1 - f) + v2 * f);
    		return (lerp(a1, a2, f) << 24) | (lerp(r1, r2, f) << 16) | (lerp(g1, g2, f) << 8) | lerp(b1, b2, f);
		}

		return { effect : cast v, setFactor : (f : Float) -> {
			v.color = lerpColor(v1.color, v2.color, f);
			v.alpha = hxd.Math.lerp(v1.alpha, v2.alpha, f);
			v.radius = hxd.Math.lerp(v1.radius, v2.radius, f);
			v.softness = hxd.Math.lerp(v1.softness, v2.softness, f);
		} };
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
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
		super.edit(ctx);
	}
	#end

	static var _ = Prefab.register("rfx.Vignetting", Vignetting);

}