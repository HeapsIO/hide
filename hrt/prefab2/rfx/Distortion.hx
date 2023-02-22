package hrt.prefab2.rfx;

class DistortionTonemap extends hxsl.Shader {
	static var SRC = {

		var calculatedUV : Vec2;
		@param var distortionMap : Sampler2D;
		@param var amount : Float;

		function fragment() {
			var distortionVal = distortionMap.get(calculatedUV).rg * amount;
			calculatedUV += distortionVal;
		}
	}
}

class Distortion extends RendererFX {

	var tonemap = new DistortionTonemap();
	@:s public var amount : Float = 1;

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {
			r.mark("Distortion");
			var distortionMap = r.allocTarget("distortion", true, 1.0, RG16F);
			r.ctx.setGlobal("distortion", distortionMap);
			r.setTarget(distortionMap);
			r.clear(0);
			r.draw("distortion");

			tonemap.amount = amount;
			tonemap.distortionMap = distortionMap;
			r.addShader(tonemap);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Distortion">
				<dl>
					<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
				</dl>
			</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.distortion", Distortion);

}