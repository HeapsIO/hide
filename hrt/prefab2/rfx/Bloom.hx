package hrt.prefab2.rfx;

class BloomTonemap extends hxsl.Shader {
	static var SRC = {
		@param var bloomTexture : Sampler2D;
		var calculatedUV : Vec2;
		var hdrColor : Vec4;
		function fragment() {
			hdrColor.rgb += bloomTexture.get(calculatedUV).rgb;
		}
	}
}

@:access(h3d.scene.Renderer)
class Bloom extends RendererFX {

	var bloomPass = new h3d.pass.ScreenFx(new hrt.shader.Bloom());
	var bloomBlur = new h3d.pass.Blur();
	var tonemap = new BloomTonemap();

	@:s public var size : Float;
	@:s public var threshold : Float;
	@:s public var intensity : Float = 1;
	@:s public var blur : Float;
	@:s public var saturation : Float;
	@:s public var blurQuality : Float = 1;
	@:s public var blurLinear : Float;

	function new(?parent, shared: ContextShared) {
		super(parent, shared);
		size = 0.5;
		blur = 3;
		threshold = 0.5;
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {
			r.mark("Bloom");
			var bloom = r.allocTarget("bloom", false, size, RGBA16F);
			var ctx = r.ctx;
			ctx.engine.pushTarget(bloom);
			bloomPass.shader.texture = ctx.getGlobal("hdrMap");
			bloomPass.shader.threshold = threshold;
			bloomPass.shader.intensity = intensity;
			bloomPass.shader.colorMatrix.identity();
			bloomPass.shader.colorMatrix.colorSaturate(saturation);
			bloomPass.render();
			ctx.engine.popTarget();

			bloomBlur.radius = blur;
			bloomBlur.quality = blurQuality;
			bloomBlur.linear = blurLinear;
			bloomBlur.apply(ctx, bloom);

			tonemap.bloomTexture = bloom;
			r.addShader(tonemap);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
			<dt>Intensity</dt><dd><input type="range" min="0" max="2" field="intensity"/></dd>
			<dt>Threshold</dt><dd><input type="range" min="0" max="1" field="threshold"/></dd>
			<dt>Size</dt><dd><input type="range" min="0" max="1" field="size"/></dd>
			<dt>Blur</dt><dd><input type="range" min="0" max="20" field="blur"/></dd>
			<dt>Saturation</dt><dd><input type="range" min="-1" max="1" field="saturation"/></dd>
			<dt>Blur Quality</dt><dd><input type="range" min="0" max="1" field="blurQuality"/></dd>
			<dt>Blur Linear</dt><dd><input type="range" min="0" max="1" field="blurLinear"/></dd>
			</dl>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.bloom", Bloom);

}