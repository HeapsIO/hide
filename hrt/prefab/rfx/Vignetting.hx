package hrt.prefab.rfx;

import hrt.prefab.rfx.RendererFX;
import hrt.prefab.Library;
import hxd.Math;

typedef VignettingProps = {
	var color : Int;
	var alpha : Float;
	var radius : Float;
	var softness : Float;
}

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

	public function new(?parent) {
		super(parent);
		props = ({
	    	color : 0xffffff,
			alpha : 1.0,
			radius : 1.0,
			softness : 0.0,
		} : VignettingProps);
	}

	function sync( r : h3d.scene.Renderer ) {
		var ctx = r.ctx;
		var props : VignettingProps = props;
		var color = h3d.Vector.fromColor(props.color);
		color.a = props.alpha;
		vignettingPass.shader.color.load(color);
		vignettingPass.shader.radius = props.radius;
		vignettingPass.shader.softness = props.softness;
		vignettingPass.pass.setBlendMode(Alpha);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
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
		'),props);
	}
	#end

	static var _ = Library.register("rfx.Vignetting", Vignetting);

}