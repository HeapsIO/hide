package hrt.prefab.rfx;
@:access(h3d.scene.Renderer)

class SaoMerge extends h3d.shader.ScreenShader {

	static var SRC = {
		@param var screenOcclusion : Sampler2D;
		@param var materialOcclusionIntensity : Float;
		@ignore @param var materialOcclusion : Channel;

		function fragment() {
			pixelColor.rgb = screenOcclusion.get(calculatedUV).xxx;
			pixelColor.rgb *= mix(1.0, materialOcclusion.get(calculatedUV).x, materialOcclusionIntensity);
		}
	}
}

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
	@:s public var USE_START_FADE : Bool = false;
	@:s public var startFadeStart : Float = 0.0;
	@:s public var startFadeEnd : Float = 50.0;
	@:s public var USE_FADE : Bool = false;
	@:s public var fadeStart: Float = 100.0;
	@:s public var fadeEnd: Float = 200.0;
	@:s public var useScalableBias : Bool;

	var sao : h3d.pass.ScalableAO;
	var saoBlur = new h3d.pass.Blur();
	var saoCopy = new h3d.pass.Copy();
	var saoMergePass = new h3d.pass.ScreenFx(new SaoMerge());
	var saoTex : h3d.mat.Texture;

	function new(parent, shared: ContextShared) {
		super(parent, shared);
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
			if ( intensity <= 0.0 )
				return;
			r.mark("SSAO");
			if( sao == null ) sao = new h3d.pass.ScalableAO();
			var ctx = r.ctx;
			saoTex = r.allocTarget("sao",false, size); // TODO : R8
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
			sao.shader.noiseScale.set(noiseScale, noiseScale);
			if( noiseTexturePath != null )
				sao.shader.noiseTexture = loadNoiseTexture(noiseTexturePath, Repeat);
			else
				sao.shader.noiseTexture = h3d.mat.Texture.genNoise(128);
			sao.shader.USE_START_FADE = USE_START_FADE;
			sao.shader.startFadeStart = startFadeStart;
			sao.shader.startFadeEnd = startFadeEnd;
			sao.shader.USE_FADE = USE_FADE;
			sao.shader.fadeStart = fadeStart;
			sao.shader.fadeEnd = fadeEnd;
			sao.shader.USE_SCALABLE_BIAS = useScalableBias;
			sao.apply(depth.texture,normal.texture,ctx.camera);
			ctx.engine.popTarget();

			saoBlur.radius = blur;
			saoBlur.quality = blurQuality;
			saoBlur.apply(ctx, saoTex);

			var saoMerge = r.allocTarget("saoMerge",false, 1.0);
			ctx.engine.pushTarget(saoMerge);
			saoMergePass.shader.materialOcclusionIntensity = microIntensity;
			saoMergePass.shader.materialOcclusionChannel = occlu.channel;
			saoMergePass.shader.materialOcclusion = occlu.texture;
			saoMergePass.shader.screenOcclusion = saoTex;
			saoMergePass.render();
			ctx.engine.popTarget();

			saoCopy.pass.setColorChannel(occlu.channel);
			saoCopy.apply(saoMerge, occlu.texture);
		}
	}

	override function modulate(t : Float) {
		var s : Sao = cast super.modulate(t);
		s.intensity = this.intensity * t;
		return s;
	}

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var s1 : Sao = cast r1;
		var s2 : Sao = cast r2;

		var s = new Sao(null, null);
		s.size = s1.size;
		s.blur = s1.blur;
		s.blurQuality = s1.blurQuality;
		s.noiseScale = s1.noiseScale;
		s.samples = s1.samples;
		s.radius = s1.radius;
		s.intensity = s1.intensity;
		s.bias = s1.bias;
		s.microIntensity = s1.microIntensity;
		s.useWorldUV = s1.useWorldUV;
		s.noiseTexturePath = s1.noiseTexturePath;
		s.USE_START_FADE = s1.USE_START_FADE;
		s.startFadeStart = s1.startFadeStart;
		s.startFadeEnd = s1.startFadeEnd;
		s.USE_FADE = s1.USE_FADE;
		s.fadeStart = s1.fadeStart;
		s.fadeEnd = s1.fadeEnd;
		s.useScalableBias = s1.useScalableBias;

		return { effect : cast s, setFactor : (f : Float) -> {
			s.size = hxd.Math.lerp(s1.size, s2.size, f);
			s.blur = hxd.Math.lerp(s1.blur, s2.blur, f);
			s.blurQuality = hxd.Math.lerp(s1.blurQuality, s2.blurQuality, f);
			s.noiseScale = hxd.Math.lerp(s1.noiseScale, s2.noiseScale, f);
			s.samples = Std.int(hxd.Math.lerp(s1.samples, s2.samples, f));
			s.radius = hxd.Math.lerp(s1.radius, s2.radius, f);
			s.intensity = hxd.Math.lerp(s1.intensity, s2.intensity, f);
			s.bias = hxd.Math.lerp(s1.bias, s2.bias, f);
			s.microIntensity = hxd.Math.lerp(s1.microIntensity, s2.microIntensity, f);
			s.useWorldUV = f < 0.5 ? s1.useWorldUV : s2.useWorldUV;
			s.noiseTexturePath = f < 0.5 ? s1.noiseTexturePath : s2.noiseTexturePath;
			s.USE_START_FADE = f < 0.5 ? s1.USE_START_FADE : s2.USE_START_FADE;
			s.startFadeStart = hxd.Math.lerp(s1.startFadeStart, s2.startFadeStart, f);
			s.startFadeEnd = hxd.Math.lerp(s1.startFadeEnd, s2.startFadeEnd, f);
			s.USE_FADE = f < 0.5 ? s1.USE_FADE : s2.USE_FADE;
			s.fadeStart = hxd.Math.lerp(s1.fadeStart, s2.fadeStart, f);
			s.fadeEnd = hxd.Math.lerp(s1.fadeEnd, s2.fadeEnd, f);
			s.useScalableBias = f < 0.5 ? s1.useScalableBias : s2.useScalableBias;
		} };
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="SSAO">
			<dl>
				<dt>Intensity</dt><dd><input type="range" min="0" max="10" field="intensity"/></dd>
				<dt>Radius</dt><dd><input type="range" min="0" max="10" field="radius"/></dd>
				<dt>Bias</dt><dd><input type="range" min="0" max="0.5" field="bias"/></dd>
				<dt>Use Scalable Bias</dt><dd><input type="checkbox" field="useScalableBias"/></dd>
				<dt>Texture Size</dt><dd><input type="range" min="0" max="1" field="size"/></dd>
				<dt>Samples</dt><dd><input type="range" min="3" max="127" field="samples" step="1"/></dd>
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
		</div>
		<div class="group" name="Start Fade">
			<dl>
				<dt>Use start fade</dt><dd><input type="checkbox" field="USE_START_FADE"/></dd>
				<dt>Fade start</dt><dd><input type="range" field="startFadeStart"/></dd>
				<dt>Fade end</dt><dd><input type="range" field="startFadeEnd"/></dd>
			</dl>
		</div>
		<div class="group" name="End Fade">
			<dl>
				<dt>Use end fade</dt><dd><input type="checkbox" field="USE_FADE"/></dd>
				<dt>Fade start</dt><dd><input type="range" field="fadeStart"/></dd>
				<dt>Fade end</dt><dd><input type="range" field="fadeEnd"/></dd>
			</dl>
		</div>
		'),this, function(pname) {
			ctx.onChange(this,pname);
		});
	}
	#end

	static var _ = Prefab.register("rfx.sao", Sao);

}
