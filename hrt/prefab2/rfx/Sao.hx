package hrt.prefab2.rfx;
@:access(h3d.scene.Renderer)
class Sao extends RendererFX {

	@:s public var size : Float = 1;
	@:s public var blur : Float;
	@:s public var blurQuality : Float = 1;
	@:s public var noiseScale : Float = 1;
	@:s public var samples : Int;
	@:s public var radius : Float;
	@:s public var intensity : Float = 1;
	@:s public var bias : Float;
	@:s public var microIntensity : Float = 1;
	@:s public var useWorldUV : Bool;
	@:s public var noiseTexturePath: String;

	var sao : h3d.pass.ScalableAO;
	var saoBlur = new h3d.pass.Blur();
	var saoCopy = new h3d.pass.Copy();

	function new(?parent) {
		super(parent);
		blur = 5;
		samples = 30;
		radius = 1;
		bias = 0.1;
	}

	function loadNoiseTexture(path : String, ?wrap : h3d.mat.Data.Wrap){
		if( path != null ) {
			var texture = hxd.res.Loader.currentInstance.load(path).toTexture();
			if( texture == null ) return null;
			if( wrap != null ) texture.wrap = wrap;
			// Need mipmap for later
			return texture;
		}
		return null;
	}

	override function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Lighting ) {
			r.mark("SSAO");
			if( sao == null ) sao = new h3d.pass.ScalableAO();
			var ctx = r.ctx;
			var saoTex = r.allocTarget("sao",false, size); // TODO : R8
			var normal : hxsl.ChannelTexture = ctx.getGlobal("normalMap");
			var depth : hxsl.ChannelTexture = ctx.getGlobal("depthMap");
			var occlu : hxsl.ChannelTexture = ctx.getGlobal("occlusionMap");
			ctx.engine.pushTarget(saoTex);
			sao.shader.numSamples = samples;
			sao.shader.sampleRadius	= radius;
			sao.shader.intensity = intensity - 1;
			sao.shader.bias = bias * bias;
			sao.shader.depthTextureChannel = depth.channel;
			sao.shader.normalTextureChannel = normal.channel;
			sao.shader.useWorldUV = useWorldUV;
			sao.shader.microOcclusion = occlu.texture;
			sao.shader.microOcclusionChannel = occlu.channel;
			sao.shader.microOcclusionIntensity = microIntensity;
			sao.shader.noiseScale.set(noiseScale, noiseScale);
			if( noiseTexturePath != null )
				sao.shader.noiseTexture = loadNoiseTexture(noiseTexturePath, Repeat);
			else
				sao.shader.noiseTexture = h3d.mat.Texture.genNoise(128);
			sao.apply(depth.texture,normal.texture,ctx.camera);
			ctx.engine.popTarget();

			saoBlur.radius = blur;
			saoBlur.quality = blurQuality;
			saoBlur.apply(ctx, saoTex);

			saoCopy.pass.setColorChannel(occlu.channel);
			saoCopy.apply(saoTex, occlu.texture);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="SSAO">
			<dl>
				<dt>Intensity</dt><dd><input type="range" min="0" max="10" field="intensity"/></dd>
				<dt>Radius</dt><dd><input type="range" min="0" max="10" field="radius"/></dd>
				<dt>Bias</dt><dd><input type="range" min="0" max="0.5" field="bias"/></dd>
				<dt>Texture Size</dt><dd><input type="range" min="0" max="1" field="size"/></dd>
				<dt>Samples</dt><dd><input type="range" min="3" max="255" field="samples" step="1"/></dd>
				<dt>Materials occlusion</dt><dd><input type="range" min="0" max="1" field="microIntensity"/></dd>
			</dl>
		</div>
		<div class="group" name="Noise">
			<dl>
				<dt>Scale</dt><dd><input type="range" min="0" max="1" field="noiseScale"/></dd>
				<dt>Use World UV</dt><dd><input type="checkbox" field="useWorldUV"/></dd>
				<dt>Texture</dt><dd><input type="texturepath" field="noiseTexturePath"/></dd>
			</dl>
		</div>
		<div class="group" name="Blur">
			<dl>
				<dt>Size</dt><dd><input type="range" min="0" max="10" field="blur"/></dd>
				<dt>Quality</dt><dd><input type="range" min="0" max="1" field="blurQuality"/></dd>
			</dl>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.sao", Sao);

}
