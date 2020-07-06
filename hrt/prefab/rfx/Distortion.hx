package hrt.prefab.rfx;

typedef DistortionProps = {
}

class DistortionTonemap extends hxsl.Shader {
	static var SRC = {

		var calculatedUV : Vec2;
		@param var distortionMap : Sampler2D;

		function fragment() {
			var distortionVal = distortionMap.get(calculatedUV).rg;
			calculatedUV += distortionVal;
		}
	}
}

class Distortion extends RendererFX {

	var tonemap = new DistortionTonemap();

	public function new(?parent) {
		super(parent);
		props = ({
		} : DistortionProps);
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {
			r.mark("Distortion");
			var p : DistortionProps = props;

			r.mark("Distortion");
			var distortionMap = r.allocTarget("distortion", true, 1.0, RG16F);
			r.ctx.setGlobal("distortion", distortionMap);
			r.setTarget(distortionMap);
			r.clear(0);
			r.draw("distortion");

			tonemap.distortionMap = distortionMap;
			r.addShader(tonemap);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Distortion">
				<dl>
				</dl>
			</div>
		'),props);
	}
	#end

	static var _ = Library.register("rfx.distortion", Distortion);

}